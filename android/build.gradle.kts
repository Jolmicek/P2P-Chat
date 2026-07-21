allprojects {
    repositories {
        google()
        mavenCentral()
    }

    configurations.all {
        resolutionStrategy {
            // Força todas as dependências do Kotlin a usarem a versão moderna unificada
            force("org.jetbrains.kotlin:kotlin-stdlib:1.9.22")
            force("org.jetbrains.kotlin:kotlin-stdlib-common:1.9.22")
            
            // Rejeita e descarta completamente as versões antigas dos módulos JDK separatistas
            exclude(group = "org.jetbrains.kotlin", module = "kotlin-stdlib-jdk7")
            exclude(group = "org.jetbrains.kotlin", module = "kotlin-stdlib-jdk8")
            
            eachDependency {
                if (requested.group == "org.jetbrains.kotlin") {
                    useVersion("1.9.22")
                }
            }
        }
    }
}
