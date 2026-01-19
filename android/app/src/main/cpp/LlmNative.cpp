#include <jni.h>
#include <android/log.h>

#include <mutex>
#include <string>
#include <vector>

#include "llama.h"

namespace {
constexpr const char * kTag = "LlmNative";

std::mutex g_mutex;
bool g_backend_ready = false;
llama_model * g_model = nullptr;
llama_context * g_ctx = nullptr;
int g_n_ctx = 2048;
int g_n_threads = 4;

void clear_state() {
    if (g_ctx) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
}

std::vector<llama_token> tokenize(const std::string & text) {
    const llama_vocab * vocab = llama_model_get_vocab(g_model);
    int32_t n_tokens = llama_tokenize(
        vocab,
        text.c_str(),
        static_cast<int32_t>(text.size()),
        nullptr,
        0,
        true,
        true
    );
    if (n_tokens < 0) {
        n_tokens = -n_tokens;
    }
    std::vector<llama_token> tokens(static_cast<size_t>(n_tokens));
    llama_tokenize(
        vocab,
        text.c_str(),
        static_cast<int32_t>(text.size()),
        tokens.data(),
        static_cast<int32_t>(tokens.size()),
        true,
        true
    );
    return tokens;
}

std::string detokenize(llama_token token) {
    const llama_vocab * vocab = llama_model_get_vocab(g_model);
    std::vector<char> buffer(256);
    int32_t written = llama_token_to_piece(
        vocab,
        token,
        buffer.data(),
        static_cast<int32_t>(buffer.size()),
        0,
        false
    );

    if (written < 0) {
        buffer.resize(static_cast<size_t>(-written));
        written = llama_token_to_piece(
            vocab,
            token,
            buffer.data(),
            static_cast<int32_t>(buffer.size()),
            0,
            false
        );
    } else if (written > static_cast<int32_t>(buffer.size())) {
        buffer.resize(static_cast<size_t>(written));
        written = llama_token_to_piece(
            vocab,
            token,
            buffer.data(),
            static_cast<int32_t>(buffer.size()),
            0,
            false
        );
    }

    if (written <= 0) {
        return {};
    }
    return std::string(buffer.data(), static_cast<size_t>(written));
}

void add_batch_token(
    llama_batch & batch,
    llama_token token,
    llama_pos pos,
    llama_seq_id seq_id,
    bool output_logits
) {
    batch.token[batch.n_tokens] = token;
    batch.pos[batch.n_tokens] = pos;
    batch.n_seq_id[batch.n_tokens] = 1;
    batch.seq_id[batch.n_tokens][0] = seq_id;
    batch.logits[batch.n_tokens] = output_logits;
    batch.n_tokens++;
}
} // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_prescription_1normalizer_LlmNative_loadModel(
    JNIEnv * env,
    jobject /*thiz*/,
    jstring path,
    jint nCtx,
    jint nThreads
) {
    const char * c_path = env->GetStringUTFChars(path, nullptr);
    if (!c_path) {
        return JNI_FALSE;
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    clear_state();

    if (!g_backend_ready) {
        llama_backend_init();
        g_backend_ready = true;
    }

    g_n_ctx = nCtx;
    g_n_threads = nThreads;

    llama_model_params mparams = llama_model_default_params();
    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = g_n_ctx;
    cparams.n_threads = g_n_threads;
    cparams.n_threads_batch = g_n_threads;

    g_model = llama_model_load_from_file(c_path, mparams);
    env->ReleaseStringUTFChars(path, c_path);

    if (!g_model) {
        __android_log_print(ANDROID_LOG_ERROR, kTag, "Failed to load model");
        return JNI_FALSE;
    }

    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) {
        __android_log_print(ANDROID_LOG_ERROR, kTag, "Failed to create context");
        clear_state();
        return JNI_FALSE;
    }

    return JNI_TRUE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_prescription_1normalizer_LlmNative_infer(
    JNIEnv * env,
    jobject /*thiz*/,
    jstring prompt,
    jint maxTokens,
    jfloat temperature
) {
    const char * c_prompt = env->GetStringUTFChars(prompt, nullptr);
    if (!c_prompt) {
        return env->NewStringUTF("");
    }

    std::string output;

    {
        std::lock_guard<std::mutex> lock(g_mutex);
        if (!g_ctx || !g_model) {
            env->ReleaseStringUTFChars(prompt, c_prompt);
            return env->NewStringUTF("");
        }

        llama_memory_t memory = llama_get_memory(g_ctx);
        llama_memory_clear(memory, true);
        llama_set_n_threads(g_ctx, g_n_threads, g_n_threads);

        const std::string prompt_text(c_prompt);
        auto tokens = tokenize(prompt_text);
        if (tokens.empty()) {
            env->ReleaseStringUTFChars(prompt, c_prompt);
            return env->NewStringUTF("");
        }
        if (static_cast<int>(tokens.size()) >= g_n_ctx) {
            const int keep = g_n_ctx - 1;
            tokens = std::vector<llama_token>(tokens.end() - keep, tokens.end());
        }

        llama_batch batch = llama_batch_init(static_cast<int32_t>(tokens.size()), 0, 1);
        for (size_t i = 0; i < tokens.size(); ++i) {
            add_batch_token(
                batch,
                tokens[i],
                static_cast<llama_pos>(i),
                0,
                i + 1 == tokens.size()
            );
        }

        if (llama_decode(g_ctx, batch) != 0) {
            llama_batch_free(batch);
            env->ReleaseStringUTFChars(prompt, c_prompt);
            return env->NewStringUTF("");
        }
        llama_batch_free(batch);

        auto sampler_params = llama_sampler_chain_default_params();
        llama_sampler * sampler = llama_sampler_chain_init(sampler_params);
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40));
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9f, 1));
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));

        const llama_vocab * vocab = llama_model_get_vocab(g_model);
        const llama_token eos = llama_vocab_eos(vocab);

        llama_pos n_past = static_cast<llama_pos>(tokens.size());
        for (int i = 0; i < maxTokens; i++) {
            llama_token next = llama_sampler_sample(sampler, g_ctx, 0);
            if (next == eos) {
                break;
            }

            output += detokenize(next);
            llama_sampler_accept(sampler, next);

            llama_batch next_batch = llama_batch_init(1, 0, 1);
            add_batch_token(next_batch, next, n_past, 0, true);
            if (llama_decode(g_ctx, next_batch) != 0) {
                llama_batch_free(next_batch);
                break;
            }
            llama_batch_free(next_batch);
            n_past++;
        }

        llama_sampler_free(sampler);
    }

    env->ReleaseStringUTFChars(prompt, c_prompt);
    return env->NewStringUTF(output.c_str());
}
