package com.inbox.md_reader

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.inbox.md_reader/file"

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
                val uri: Uri? = intent.data
                uri?.let { fileUri ->
                    try {
                        // 读取文件内容
                        val content = readFileContent(fileUri)
                        val path = fileUri.path ?: "unknown"

                        // 发送给 Flutter
                        flutterEngine?.let { engine ->
                            MethodChannel(
                                engine.dartExecutor.binaryMessenger,
                                CHANNEL
                            ).invokeMethod("loadContent", mapOf(
                                "path" to path,
                                "content" to content
                            ))
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
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
                    try {
                        // 读取文件内容
                        val content = readFileContent(fileUri)
                        val path = fileUri.path ?: "unknown"

                        // 发送给 Flutter
                        flutterEngine?.let { engine ->
                            MethodChannel(
                                engine.dartExecutor.binaryMessenger,
                                CHANNEL
                            ).invokeMethod("loadContent", mapOf(
                                "path" to path,
                                "content" to content
                            ))
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        }
    }

    private fun readFileContent(uri: Uri): String {
        val stringBuilder = StringBuilder()
        contentResolver.openInputStream(uri)?.use { inputStream ->
            BufferedReader(InputStreamReader(inputStream)).use { reader ->
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
