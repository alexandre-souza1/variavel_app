import java.net.URI
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.google.gms.google-services")
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Supply a public URL, never credentials or tokens. It is embedded in the APK.
val appUrl = providers.gradleProperty("appUrl")
    .orElse(providers.environmentVariable("ANDROID_APP_URL"))
    .orElse(providers.gradleProperty("defaultAppUrl"))
    .orNull ?: error("Informe -PappUrl=https://seu-dominio ou ANDROID_APP_URL.")
val endpoint = URI(appUrl)
require(endpoint.scheme == "https" && !endpoint.host.isNullOrBlank() &&
    endpoint.rawUserInfo == null && endpoint.rawQuery == null && endpoint.rawFragment == null &&
    (endpoint.port == -1 || endpoint.port in 1..65535)) {
    "appUrl deve ser HTTPS, sem credenciais, query string ou fragmento."
}

val signingProperties = Properties().apply {
    rootProject.file("keystore.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
fun signingValue(property: String, environment: String): String? =
    providers.environmentVariable(environment).orNull?.takeIf { it.isNotBlank() }
        ?: signingProperties.getProperty(property)
val releaseStore = signingValue("storeFile", "WORKSTATION_KEYSTORE_PATH")

android {
    namespace = "br.com.log20.variavel"
    compileSdk = 35

    defaultConfig {
        applicationId = "br.com.log20.variavel"
        minSdk = 28
        targetSdk = 35
        versionCode = 6
        versionName = "0.3.1"
        buildConfigField("String", "APP_URL", "\"${endpoint.toASCIIString()}\"")
    }

    buildFeatures { buildConfig = true }
    if (releaseStore != null) {
        signingConfigs {
            create("production") {
                storeFile = file(releaseStore)
                storePassword = signingValue("storePassword", "WORKSTATION_STORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "WORKSTATION_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "WORKSTATION_KEY_PASSWORD")
            }
        }
        buildTypes.getByName("release").signingConfig = signingConfigs.getByName("production")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name == "assembleRelease" || it.name == "bundleRelease" }) {
        check(releaseStore != null) { "Configure a assinatura de produção conforme android/README.md." }
    }
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.3.0"))
    implementation("com.google.firebase:firebase-messaging")
    testImplementation("junit:junit:4.13.2")
    implementation("dev.hotwire:core:1.3.1")
    implementation("dev.hotwire:navigation-fragments:1.3.1")
    implementation("com.google.android.material:material:1.12.0")
}
