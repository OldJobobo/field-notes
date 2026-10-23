plugins {
    id("com.android.application")
}

android {
    namespace = "com.wonderingsolutions.fieldnotes"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.wonderingsolutions.fieldnotes"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// The tests read the bridge's fixtures in ../../bridge/testdata, so a fixture change must rerun them.
tasks.withType<Test>().configureEach {
    inputs.dir("../../bridge/testdata").withPathSensitivity(PathSensitivity.RELATIVE)
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
}
