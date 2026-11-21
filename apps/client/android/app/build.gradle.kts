import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Production's release signing key, Step 11G. key.properties is Git-ignored
// and names a keystore kept outside the repository; make both with
// make-release-key.ps1. Never commit either.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.example.veloraug"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // From pubspec.yaml's version.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    // dev is the default (pubspec.yaml's default-flavor); production is
    // `--flavor prod`. Each has its own app ID and sign-in host, which must
    // match the Neon Android client and that host's assetlinks.json.
    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationId = "com.example.veloraug"
            manifestPlaceholders["authHost"] = "veloraug-auth-dev.pages.dev"
            // Development builds, release included, use the debug key.
            signingConfig = signingConfigs.getByName("debug")
        }
        create("prod") {
            dimension = "environment"
            // D5. It can never change once people have installed it.
            applicationId = "com.veloraug.app"
            manifestPlaceholders["authHost"] = "auth.veloraug.com"
            // Only the release key: without key.properties a production
            // build stops, rather than being signed with the debug key.
            signingConfig = signingConfigs.findByName("release")
        }
    }

    buildTypes {
        release {
            // Flavors choose the key; this stays unset so prod can't fall
            // back to debug signing.
        }
    }
}

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Prod", ignoreCase = false) } &&
        !keyProperties.containsKey("storeFile")) {
        throw GradleException(
            "Production builds need android/key.properties and the release key. " +
                "Run android/make-release-key.ps1 first (see README.md)."
        )
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
