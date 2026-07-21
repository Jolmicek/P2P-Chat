buildscript {
    // Definimos a variável para que os plugins antigos do Flutter a consigam ler
    extra["kotlin_version"] = "1.9.22" 
    
    repositories {
        google()
        mavenCentral()
    }
    // NOTA IMPORTANTE: O bloco 'dependencies' com o classpath NÃO deve estar aqui!
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
