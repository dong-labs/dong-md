package com.inbox.md_reader

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.inbox.md_reader/file"

    // Flutter 还没就绪时，先缓存住 Intent 带来的文件内容，
    // 等 Dart 端 initState 注册好 handler 后主动调用 consumeLaunchContent 取走。
    // 这样冷启动（从分享/打开方式唤起）也不会丢内容。
    @Volatile
    private var pendingContent: Map<String, Any>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_VIEW -> {
                intent.data?.let { fileUri ->
                    cacheFromFileUri(fileUri)
                }
            }
            Intent.ACTION_SEND -> {
                // 处理微信等应用分享文件
                val uri: Uri? = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
                uri?.let { fileUri ->
                    cacheFromFileUri(fileUri)
                }
            }
        }
    }

    private fun cacheFromFileUri(fileUri: Uri) {
        try {
            val content = readFileContent(fileUri)
            val path = fileUri.path ?: "unknown"
            pendingContent = mapOf(
                "path" to path,
                "content" to content
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                if (call.method == "consumeLaunchContent") {
                    val data = pendingContent
                    pendingContent = null
                    result.success(data)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun readFileContent(uri: Uri): String {
        val stringBuilder = StringBuilder()
        contentResolver.openInputStream(uri)?.use { inputStream ->
            // 显式 UTF-8，避免某些机型默认编码导致中文/特殊字符乱码
            BufferedReader(InputStreamReader(inputStream, StandardCharsets.UTF_8)).use { reader ->
                var line: String? = reader.readLine()
                while (line != null) {
                    stringBuilder.append(line).append("\n")
                    line = reader.readLine()
                }
            }
        }
        return stringBuilder.toString()
    }
}
