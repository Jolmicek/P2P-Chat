// O segredo está aqui: declarar na raiz do ficheiro para o shared_preferences ver!
rootProject.extra["kotlin_version"] = "1.9.22"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
