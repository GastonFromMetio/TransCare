package com.example.prescription_normalizer

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "llm_infer"
    private var modelPath: String? = null
    private var modelReady: Boolean = false
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadModel" -> {
                    val assetPath = call.argument<String>("assetPath")
                    val localPath = call.argument<String>("localPath")
                    val nCtx = call.argument<Int>("nCtx") ?: 2048
                    val nThreads = call.argument<Int>("nThreads") ?: 4

                    Thread {
                        val resolvedPath = when {
                            !localPath.isNullOrBlank() -> localPath
                            !assetPath.isNullOrBlank() -> copyAssetToFile(assetPath)
                            else -> null
                        }

                        if (resolvedPath == null) {
                            modelReady = false
                            Log.e("LlmNative", "Model path unresolved")
                            mainHandler.post { result.success(false) }
                            return@Thread
                        }

                        modelPath = resolvedPath
                        Log.i("LlmNative", "Loading model at $resolvedPath")
                        modelReady = LlmNative.loadModel(resolvedPath, nCtx, nThreads)
                        Log.i("LlmNative", "Model ready: $modelReady")
                        mainHandler.post { result.success(modelReady) }
                    }.start()
                }
                "infer" -> {
                    val prompt = call.argument<String>("prompt") ?: ""
                    val maxTokens = call.argument<Int>("maxTokens") ?: 256
                    val temperature = call.argument<Double>("temperature") ?: 0.1

                    if (!modelReady || modelPath.isNullOrBlank()) {
                        result.success("")
                        return@setMethodCallHandler
                    }

                    Thread {
                        Log.i("LlmNative", "Infer start, maxTokens=$maxTokens")
                        val output = LlmNative.infer(
                            prompt,
                            maxTokens,
                            temperature.toFloat(),
                        )
                        Log.i("LlmNative", "Infer done, chars=${output.length}")
                        mainHandler.post { result.success(output) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun copyAssetToFile(assetPath: String): String? {
        return try {
            val filename = assetPath.substringAfterLast('/')
            val dir = getDir("models", Context.MODE_PRIVATE)
            val outFile = java.io.File(dir, filename)

            if (!outFile.exists() || outFile.length() == 0L) {
                val flutterPath = "flutter_assets/$assetPath"
                Log.i("LlmNative", "Copying asset $flutterPath to ${outFile.absolutePath}")
                assets.open(flutterPath).use { input ->
                    outFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
            }
            outFile.absolutePath
        } catch (e: Exception) {
            Log.e("LlmNative", "Asset copy failed: ${e.message}")
            null
        }
    }
}
