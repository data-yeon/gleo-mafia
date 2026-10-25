plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.gleo.mafia.pleos"
    compileSdk = 34

    defaultConfig {
        // Matches the minSdk 28 requirement in the Pleos Connect guide.
        minSdk = 28
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // Godot Android library: provided by the Godot app at runtime, so compile-only.
    compileOnly("org.godotengine:godot:4.7.2.stable")
    // Pleos Vehicle SDK 2.3.2 (the guide says 2.3.1, but only 2.3.2 exists in the Pleos repository).
    implementation("ai.pleos.playground:Vehicle:2.3.2")
}
