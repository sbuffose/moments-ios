# Moments 📸

**Una app nativa de iPhone para organizar inteligentemente tu biblioteca de fotos, con total privacidad.**

Moments analiza tus fotos y videos localmente en tu dispositivo para ayudarte a:
- 🧹 **Limpiar** fotos duplicadas, borrosas, screenshots y tomas accidentales
- 📅 **Organizar** tus recuerdos en momentos y detectar viajes
- 🗺️ **Descubrir** los lugares que visitaste en un mapa interactivo
- 👥 **Encontrar** fotos por personas y recordar cumpleaños

## 🚀 Requisitos

- **iOS 17.0** o superior
- **Xcode 15.0** o superior (para compilar localmente)
- iPhone con biblioteca de fotos

## 📱 Cómo ejecutar la app

### Opción 1: TestFlight (Recomendado)

La app se despliega automáticamente a TestFlight cuando hay cambios en `main`.

### Opción 2: Compilar localmente en Xcode

1. Cloná o descargá este repositorio
2. Instalá XcodeGen si no lo tenés: `brew install xcodegen`
3. Generá el proyecto: `xcodegen generate`
4. Abrí `Moments.xcodeproj` en Xcode
5. Seleccioná tu iPhone o un simulador como destino
6. Presioná `Cmd + R` para compilar y ejecutar

### Configuración adicional (desarrollo local)

1. **Team de desarrollo**: En Xcode, seleccioná tu cuenta de desarrollador en `Signing & Capabilities`
2. **Bundle Identifier**: Si cambiás el bundle ID, asegurate de actualizarlo en `project.yml`

## 🚢 Despliegue a TestFlight

El proyecto incluye un workflow de GitHub Actions que automatiza el despliegue a TestFlight.

### Configuración de secretos

En tu repositorio de GitHub, configurá estos secretos en **Settings > Secrets and variables > Actions**:

| Secreto | Descripción |
|---------|-------------|
| `ASC_KEY_ID` | ID de la clave de App Store Connect API (ej: `ABC123DEF4`) |
| `ASC_ISSUER_ID` | Issuer ID de App Store Connect (UUID) |
| `ASC_PRIVATE_KEY` | Contenido completo del archivo `.p8` de la API key |

### Cómo obtener las credenciales

1. Andá a [App Store Connect > Users and Access > Integrations > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
2. Generá una nueva clave con permisos de **App Manager** o superior
3. Descargá el archivo `.p8` (solo se puede descargar una vez)
4. Copiá el **Key ID** y el **Issuer ID**
5. El contenido del `.p8` va en `ASC_PRIVATE_KEY` (incluyendo `-----BEGIN PRIVATE KEY-----` y `-----END PRIVATE KEY-----`)

### Proceso de despliegue

El workflow se ejecuta automáticamente en:
- Cada push a `main`
- Manualmente via **Actions > Build and Deploy to TestFlight > Run workflow**

El workflow:
1. Genera el proyecto con XcodeGen
2. Usa el número de run como `CURRENT_PROJECT_VERSION` (build number único)
3. Archiva con firma automática usando la API key de App Store Connect
4. Exporta el IPA con método `app-store-connect`
5. Sube a TestFlight con `xcrun altool`

### Notas importantes

- El bundle ID es `com.sbuffose.moments`
- El Team ID es `R56Y2GZ2M9`
- La app ya debe existir en App Store Connect (el record "Moments Photos" ya está creado)
- Los nuevos builds aparecen en TestFlight en ~10-15 minutos después del upload

## 🏗️ Arquitectura del Proyecto

```
Moments/
├── .github/workflows/
│   └── testflight.yml          # CI/CD para TestFlight
├── Moments.xcodeproj/          # Proyecto Xcode (generado por XcodeGen)
├── MomentsEngine/              # Motor de análisis (Swift Package)
│   ├── Sources/
│   │   └── MomentsEngine/
│   │       ├── Analysis/       # Analizadores (Cleanup, Timeline, Places, People)
│   │       ├── Models/         # Modelos de datos puros
│   │       └── Utils/          # Utilidades
│   └── Tests/                  # Tests unitarios
├── Moments/
│   ├── Sources/
│   │   ├── App/               # Punto de entrada, estado global
│   │   ├── Models/            # Modelos SwiftData (persistencia)
│   │   ├── Services/          # PhotoKit, Vision, Geocoding
│   │   ├── ViewModels/        # Lógica de presentación
│   │   └── Views/             # Vistas SwiftUI
│   └── Resources/
│       ├── es-AR.lproj/       # Localización Español Argentina
│       ├── en.lproj/          # Localización Inglés
│       ├── Assets.xcassets/   # Iconos y colores
│       └── Info.plist         # Configuración y permisos
├── project.yml                 # Especificación XcodeGen (fuente de verdad)
└── ExportOptions.plist         # Opciones de exportación para App Store
```

## ✨ Funcionalidades

### 1. Limpieza Inteligente

Detecta automáticamente fotos que podrías querer eliminar:

| Categoría | Cómo se detecta |
|-----------|-----------------|
| Screenshots | `PHAsset.mediaSubtypes` contiene `.photoScreenshot` |
| Grabaciones de pantalla | `mediaSubtypes` contiene `.videoScreenRecording` |
| Fotos borrosas | Análisis de bordes con Core Image (Sobel) |
| Sobreexpuestas | Core Image: luminancia promedio > 0.85 |
| Subexpuestas | Core Image: luminancia promedio < 0.15 |
| Duplicados | Vision: feature prints con similitud |
| Ráfagas | `burstIdentifier` + selección de la mejor |
| Tomas accidentales | Combinación: muy oscura, sin rostros, aspecto raro |
| Documentos | Vision: detección de texto extenso |
| Videos grandes | Tamaño > 100 MB |

**Revisión**: Grid con selección múltiple o modo swipe (deslizar para conservar/eliminar).

### 2. Línea de Tiempo

- Agrupa fotos en **momentos** por tiempo (< 4 horas entre fotos) y ubicación (< 5 km)
- Detecta **viajes** cuando las fotos están > 50 km de tu ubicación habitual
- Muestra **"En este día"** con fotos de años anteriores
- Portadas automáticas priorizando fotos con rostros y buena calidad

### 3. Lugares

- Clustering de fotos por ubicación usando algoritmo DBSCAN adaptado
- Mapa interactivo con MapKit y clustering dinámico según zoom
- Reverse geocoding con CLGeocoder (cacheado 30 días)
- Detección automática de tu ubicación habitual ("casa")

### 4. Personas

- Detección de rostros con Vision (`VNDetectFaceRectanglesRequest`)
- Clustering de rostros por similitud de feature prints
- El usuario puede nombrar personas y agregar cumpleaños
- Alertas de cumpleaños próximos

## 🔬 Motor de Análisis (MomentsEngine)

El módulo `MomentsEngine` es un **Swift Package puro** sin dependencias de iOS, diseñado para:

- Ser **testeable** sin simulador ni dispositivo
- Separar la lógica de análisis de la UI
- Permitir reusar la lógica en otras plataformas (macOS, etc.)

### Ejecutar tests

```bash
cd MomentsEngine
swift test
```

Los tests cubren:
- `CleanupAnalyzerTests`: detección de screenshots, borrosas, bursts, etc.
- `TimelineAnalyzerTests`: generación de momentos, detección de viajes
- `PlaceAnalyzerTests`: clustering de lugares, detección de hogar
- `PeopleAnalyzerTests`: clustering de rostros, eventos recurrentes

## 🔒 Privacidad

**Todo el análisis se realiza en tu dispositivo.** Nunca se envían fotos ni datos a servidores externos.

Permisos requeridos (definidos en `Info.plist`):
- `NSPhotoLibraryUsageDescription`: Acceso a la biblioteca de fotos
- `NSLocationWhenInUseUsageDescription`: Para detectar viajes (opcional)

La app declara `ITSAppUsesNonExemptEncryption = NO` para simplificar el proceso de exportación.

## 🌐 Localización

La app está disponible en:
- **Español (Argentina)** - `es-AR.lproj` (idioma por defecto)
- **Inglés** - `en.lproj`

Para agregar un nuevo idioma:
1. Creá una carpeta `[código].lproj` en `Resources/`
2. Copiá `Localizable.strings` y traducí las cadenas
3. Agregá el código de idioma en `knownRegions` del proyecto

## ⚠️ Limitaciones Conocidas

### Heurísticas aproximadas
- **Fotos borrosas**: Usa detección de bordes como proxy de nitidez; algunas fotos artísticas pueden marcarse
- **Tomas accidentales**: Puede haber falsos positivos con fotos artísticas oscuras
- **Detección de fiestas/cumpleaños**: Basada en cantidad de rostros y fotos en poco tiempo

### No implementado en esta versión
- Clasificación de objetos (tortas, decoraciones) para cumpleaños
- Detección de memes vs fotos reales
- Sincronización con iCloud Photo Library (funciona con fotos locales)
- Widget de iOS

### Notas de compilación
- El proyecto usa Swift 5 con concurrencia mínima (`SWIFT_STRICT_CONCURRENCY = minimal`) para evitar warnings innecesarios
- El motor `MomentsEngine` es pure Swift y sus tests pasan en cualquier plataforma
- La app iOS completa solo puede compilarse en macOS con Xcode 15+

## 🛠️ Próximos Pasos

1. [ ] Agregar clasificación de imágenes con Core ML para detectar tortas, decoraciones
2. [ ] Implementar detección de memes usando Vision + heurísticas
3. [ ] Agregar widget de iOS para "En este día"
4. [ ] Soporte para carpetas compartidas de iCloud
5. [ ] Exportar momentos como álbumes de Fotos
6. [ ] Diseñar un ícono de app profesional

## 📄 Licencia

Este proyecto es para uso personal de Sebastián. Para uso comercial, contactar al autor.

---

**Desarrollado con ❤️ en Swift y SwiftUI**
