allprojects {
    repositories {
        google()
        mavenCentral()
    }

    configurations.all {
        // A nossa regra anterior para forçar a versão
        resolutionStrategy.eachDependency {
            if (requested.group == "org.jetbrains.kotlin") {
                useVersion("1.9.22")
            }
        }
        
        // NOVO: Remove os pacotes antigos que estão a causar os duplicados
        exclude(group = "org.jetbrains.kotlin", module = "kotlin-stdlib-jdk7")
        exclude(group = "org.jetbrains.kotlin", module = "kotlin-stdlib-jdk8")
    }
}
