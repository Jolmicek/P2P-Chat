allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // OPÇÃO NUCLEAR: Obriga TODOS os plugins (incluindo o shared_preferences)
    // a usar o Kotlin 1.9.22, quer eles queiram ou não.
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.jetbrains.kotlin") {
                useVersion("1.9.22")
            }
        }
    }
}
