#include <jni.h>
#include <stdexcept>
#include <cmath>
#include "mnn_vits_loader.hpp"
namespace {
std::string string(JNIEnv* env, jstring s) {
    const char* value = env->GetStringUTFChars(s, nullptr);
    if (!value) throw std::runtime_error("Invalid model path");
    std::string result(value); env->ReleaseStringUTFChars(s, value); return result;
}
void fail(JNIEnv* env, const std::exception& e) { env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), e.what()); }
}
extern "C" JNIEXPORT void JNICALL Java_com_niceday_memo_VitsMnn_open(JNIEnv* env, jclass, jstring path) {
    try {
        MNN_VITS::init_vits_loader(); const auto base = string(env, path) + "/vits_uma_genshin_honkai_";
        MNN_VITS::set_vits_model_path(base+"enc_fp16.mnn",base+"dec_fp16.mnn",base+"dp_fp16.mnn",base+"emb_fp16.mnn",base+"flow_fp16.mnn");
    } catch (const std::exception& e) { MNN_VITS::destroy_vits_loader(); fail(env,e); }
}
extern "C" JNIEXPORT jfloatArray JNICALL Java_com_niceday_memo_VitsMnn_generate(JNIEnv* env, jclass, jintArray ids, jintArray pause_ids, jint speaker, jfloat speed) {
    try {
        const jsize length = env->GetArrayLength(ids);
        if (!pause_ids || env->GetArrayLength(pause_ids) != length || length < 3 || length > 1024 || speaker < 0 || speaker >= 804 || !std::isfinite(speed) || speed < .5f || speed > 1.3f) throw std::runtime_error("Invalid synthesis input");
        std::vector<int> input(length); env->GetIntArrayRegion(ids,0,length,reinterpret_cast<jint*>(input.data()));
        std::vector<int> pauses(length); env->GetIntArrayRegion(pause_ids,0,length,reinterpret_cast<jint*>(pauses.data()));
        MNN_VITS::set_length_scale(1.0f/speed);
        auto audio=MNN_VITS::start_audio_infer(input,speaker,pauses,speed);
        if (audio.empty() || audio.size()>22050*90) throw std::runtime_error("Invalid audio length");
        auto result=env->NewFloatArray(static_cast<jsize>(audio.size()));
        if(result) env->SetFloatArrayRegion(result,0,static_cast<jsize>(audio.size()),audio.data()); return result;
    } catch (const std::exception& e) { fail(env,e); return nullptr; }
}
extern "C" JNIEXPORT void JNICALL Java_com_niceday_memo_VitsMnn_close(JNIEnv*, jclass) { MNN_VITS::destroy_vits_loader(); }
