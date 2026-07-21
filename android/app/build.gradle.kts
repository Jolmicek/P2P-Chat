android {
    ndkVersion = "27.0.12077973"   // <- mantém apenas esta
    namespace = "com.example.p2pchat"
    compileSdk = flutter.compileSdkVersion
    // REMOVE a linha: ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.p2pchat"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// ADICIONA ESTE BLOCO NO FUNDO DO FICHEIRO:
dependencies {
    implementation(platform("org.jetbrains.kotlin:kotlin-bom:1.9.22"))
}

configurations.all {
    exclude(group = "org.jetbrains.kotlin", module = "kotlin-stdlib-jdk7")
    exclude(group = "org.jetbrains.kotlin", module = "kotlin-stdlib-jdk8")
}
