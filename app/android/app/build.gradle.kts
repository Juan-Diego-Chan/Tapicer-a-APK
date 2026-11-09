import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Datos de firma: primero las variables de entorno TAPICERIA_*, luego key.properties.
val propiedadesLlave = Properties().apply {
    val archivo = rootProject.file("key.properties")
    if (archivo.exists()) archivo.inputStream().use { load(it) }
}

fun datoFirma(variable: String, propiedad: String): String? =
    System.getenv(variable)?.takeIf { it.isNotBlank() }
        ?: propiedadesLlave.getProperty(propiedad)?.takeIf { it.isNotBlank() }

val firmaStoreFile = datoFirma("TAPICERIA_KEYSTORE", "storeFile")
val firmaStorePassword = datoFirma("TAPICERIA_KEYSTORE_PASSWORD", "storePassword")
val firmaKeyAlias = datoFirma("TAPICERIA_KEY_ALIAS", "keyAlias")
val firmaKeyPassword = datoFirma("TAPICERIA_KEY_PASSWORD", "keyPassword")
val hayLlaveDeFirma = firmaStoreFile != null && firmaStorePassword != null &&
    firmaKeyAlias != null && firmaKeyPassword != null

android {
    namespace = "mx.tapiceria.tapiceria"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "mx.tapiceria.gestion"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Firebase (firebase_core 5.1.0 local-config.gradle) exige minSdk 24; piso del proyecto: 23.
        minSdk = maxOf(23, 24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayLlaveDeFirma) {
            create("release") {
                storeFile = file(firmaStoreFile!!)
                storePassword = firmaStorePassword
                keyAlias = firmaKeyAlias
                keyPassword = firmaKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hayLlaveDeFirma) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("Sin llave de firma: el APK de release usa la firma de depuración")
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
