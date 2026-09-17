# Hotwire Native
-keep class dev.hotwire.** { *; }
-keep interface dev.hotwire.** { *; }
-keep @dev.hotwire.navigation.destinations.HotwireDestinationDeepLink class * { *; }
-dontwarn dev.hotwire.**

# App components and destinations
-keep class br.com.log20.variavel.** extends dev.hotwire.navigation.fragments.HotwireWebFragment { *; }
-keep class br.com.log20.variavel.** extends dev.hotwire.navigation.activities.HotwireActivity { *; }
-keep class br.com.log20.variavel.VariavelApplication { *; }
-keep class br.com.log20.variavel.WorkstationMessagingService { *; }
-keep class br.com.log20.variavel.ExportFileProvider { *; }
-keep class br.com.log20.variavel.PdfActivity { *; }
-keep class br.com.log20.variavel.DownloadActivity { *; }
-keep class br.com.log20.variavel.MainActivity { *; }

# Preserve line numbers and annotations for debugging and stack traces
-keepattributes SourceFile,LineNumberTable,*Annotation*
