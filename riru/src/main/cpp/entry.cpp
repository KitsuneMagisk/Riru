#include <dlfcn.h>
#include <android_prop.h>
#include <pthread.h>
#include <rirud.h>
#include "jni_hooks.h"
#include "logging.h"
#include "module.h"
#include "hide_utils.h"
#include "magisk.h"
#include "entry.h"
#include "config.h"

static void *self_handle;
static bool self_unload_allowed;

struct SelfUnloadGuard {

    SelfUnloadGuard() {
        pthread_mutex_init(&mutex_, nullptr);
    }

    ~SelfUnloadGuard() {
        LOGD("self unload lock (destructor)");
        pthread_mutex_lock(&mutex_);

        LOGD("self unload");

        timespec ts = {.tv_sec = 0, .tv_nsec = 1000000L};
        nanosleep(&ts, nullptr);
    }

    struct Holder {
        explicit Holder(pthread_mutex_t *mutex) : mutex_(mutex) {
            LOGD("self unload lock (holder constructor)");
            pthread_mutex_lock(mutex_);
        }

        Holder(Holder &&other) noexcept: mutex_(other.mutex_) {
            other.mutex_ = nullptr;
        }

        ~Holder() {
            if (mutex_) {
                pthread_mutex_unlock(mutex_);
                LOGD("self unload unlock (holder destructor)");
            }
        }

    private:
        pthread_mutex_t *mutex_;

    public:
        Holder(const Holder &) = delete;

        void operator=(const Holder &) = delete;
    };

    auto hold() { return Holder(&mutex_); };

private:
    pthread_mutex_t mutex_{};
} self_unload_guard;

static void SelfUnload() {
    LOGD("attempt to self unload");

    [[maybe_unused]] auto holder = self_unload_guard.hold();

    pthread_t thread;
    pthread_create(&thread, nullptr, (void *(*)(void *)) &dlclose, self_handle);
    pthread_detach(thread);
}

bool Entry::IsSelfUnloadAllowed() {
    return self_unload_allowed;
}

void Entry::Unload(jboolean is_child_zygote) {
    self_unload_allowed = true;

    for (auto &module : modules::Get()) {
        if (module.allowUnload()) {
            LOGD("%s: unload", module.id.data());
            module.unload();
        } else {
            if (module.apiVersion >= 25)
                LOGD("%s: unload is not allow for this process", module.id.data());
            else {
                LOGD("%s: unload is not supported by module (API < 25), self unload is also disabled",
                     module.id.data());
                self_unload_allowed = false;
            }
        }
    }

    hide::HideFromSoList();

    // Child zygote (webview zyote or app zygote) has no "execmem" permission
    if (android_prop::GetApiLevel() < 29 && !is_child_zygote) {
        hide::HideFromMaps();
    }

    if (self_unload_allowed) {
        SelfUnload();
    }
}

extern "C" [[gnu::visibility("default")]] [[maybe_unused]] void
// NOLINTNEXTLINE
init(void *handle) {
    self_handle = handle;

    LOGI("Riru %s (%d)", riru::versionName, riru::versionCode);
    LOGI("Android %s (api %d, preview_api %d)", android_prop::GetRelease(),
         android_prop::GetApiLevel(),
         android_prop::GetPreviewApiLevel());

    constexpr auto retries = 5U;
    RirudSocket rirud{retries};

    if (!rirud.valid()) {
        LOGE("rirud connect fails");
        return;
    }

    std::string magisk_path = rirud.ReadMagiskTmpfsPath();
    if (magisk_path.empty()) {
        LOGE("failed to obtain magisk path");
        return;
    }

    magisk::SetPath(magisk_path.data());
    hide::PrepareMapsHideLibrary();
    jni::InstallHooks();
    modules::Load(rirud);
}
