package com.example.prescription_normalizer

object LlmNative {
    init {
        System.loadLibrary("llm_native")
    }

    external fun loadModel(path: String, nCtx: Int, nThreads: Int): Boolean
    external fun infer(prompt: String, maxTokens: Int, temperature: Float): String
}
