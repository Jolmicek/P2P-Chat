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

    packaging {
        resources.excludes.add("META-INF/versions/9/OSGI-INF/MANIFEST.MF")
        resources.excludes.add("META-INF/kotlin-stdlib.kotlin_module")
        resources.excludes.add("META-INF/kotlin-stdlib-jdk7.kotlin_module")
        resources.excludes.add("META-INF/kotlin-stdlib-jdk8.kotlin_module")
    }
}

// ADICIONA ESTE BLOCO NO FUNDO DO FICHEIRO:
dependencies {
    // Alinha todas as versões do Kotlin
    implementation(platform("org.jetbrains.kotlin:kotlin-bom:1.9.22"))
    
    // FORÇA as dependências fantasma a usar a versão nova (que vem vazia e não dá conflito)
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.9.22")
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.9.22")
}

configurations.all {
    resolutionStrategy {
        // Força o Gradle a rejeitar qualquer versão antiga do kotlin-stdlib-*
        force("org.jetbrains.kotlin:kotlin-stdlib:1.9.22")
        force("org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.9.22")
        force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.9.22")
        
        // Se alguma dependência insistir em puxar o 1.7.x, o Gradle descarta-a automaticamente
        eachDependency {
            if (requested.group == "org.jetbrains.kotlin") {
                useVersion("1.9.22")
            }
        }
    }
}
