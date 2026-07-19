package com.truthid.truthid_mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (não FlutterActivity) — exigência do plugin
// local_auth_android: o prompt biométrico usa androidx.biometric.BiometricPrompt,
// que precisa de uma FragmentActivity por baixo.
class MainActivity : FlutterFragmentActivity()
