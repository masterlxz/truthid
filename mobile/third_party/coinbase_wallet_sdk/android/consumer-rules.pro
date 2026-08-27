# Vendorizado do pub.dev 1.0.10 (P86): o pacote publicado referencia este
# arquivo em build.gradle mas não o inclui no tarball (bug de publish real
# do upstream), quebrando mergeReleaseConsumerProguardFiles. Vazio de
# propósito — nem o módulo nem o app (mobile/android/app/build.gradle.kts)
# habilitam minifyEnabled, então não há regras de keep pra propagar.
