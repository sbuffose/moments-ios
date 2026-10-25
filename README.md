# Moments 📸

**Una app nativa de iPhone para organizar inteligentemente tu biblioteca de fotos, con total privacidad.**

Moments analiza tus fotos y videos localmente en tu dispositivo para ayudarte a:
- 🧹 **Limpiar** fotos duplicadas, borrosas, screenshots y tomas accidentales
- 📅 **Organizar** tus recuerdos en momentos y detectar viajes
- 🗺️ **Descubrir** los lugares que visitaste en un mapa interactivo
- 👥 **Encontrar** fotos por personas y recordar cumpleaños

## 🚀 Requisitos

- **iOS 17.0** o superior
- **Xcode 15.0** o superior (para compilar)
- iPhone con biblioteca de fotos

## 📱 Cómo ejecutar la app

### Opción 1: Abrir directamente en Xcode

1. Cloná o descargá este repositorio
2. Abrí `Moments.xcodeproj` en Xcode
3. Seleccioná tu iPhone o un simulador como destino
4. Presioná `Cmd + R` para compilar y ejecutar

### Opción 2: Usar XcodeGen (recomendado)

Si tenés [XcodeGen](https://github.com/yonaskolb/XcodeGen) instalado:

```bash
# Instalar XcodeGen si no lo tenés
brew install xcodegen

# Generar el proyecto
xcodegen generate

# Abrir en Xcode
open Moments.xcodeproj
```

### Configuración adicional

1. **Team de desarrollo**: En Xcode, seleccioná tu cuenta de desarrollador en `Signing & Capabilities`
2. **Bundle Identifier**: Cambiá `com.moments.app` por uno único si vas a instalarlo en un dispositivo físico

## 🏗️ Arquitectura del Proyecto

```
Moments/
├── Moments.xcodeproj/          # Proyecto Xcode
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
└── project.yml                 # Especificación XcodeGen
```

## ✨ Funcionalidades

### 1. Limpieza Inteligente

Detecta automáticamente fotos que podrías querer eliminar:

| Categoría | Cómo se detecta |
|-----------|-----------------|
| Screenshots | `PHAsset.mediaSubtypes` contiene `.photoScreenshot` |
| Grabaciones de pantalla | `mediaSubtypes` contiene `.videoScreenRecording` |
| Fotos borrosas | Vision: score de nitidez < 0.3 |
| Sobreexpuestas | Core Image: luminancia promedio > 0.85 |
| Subexpuestas | Core Image: luminancia promedio < 0.15 |
| Duplicados | Vision: feature prints con similitud coseno > 0.95 |
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
- **Fotos borrosas**: El score de nitidez de Vision es orientativo; algunas fotos de movimiento intencional pueden marcarse
- **Tomas accidentales**: Puede haber falsos positivos con fotos artísticas oscuras
- **Detección de fiestas/cumpleaños**: Basada en cantidad de rostros y fotos en poco tiempo; no detecta tortas ni decoraciones

### No implementado en esta versión
- Clasificación de objetos (tortas, decoraciones) para cumpleaños
- Detección de memes vs fotos reales
- Sincronización con iCloud Photo Library (funciona con fotos locales)
- Widget de iOS

### Verificación en Linux
El motor `MomentsEngine` compila y sus tests pasan en cualquier plataforma con Swift 5.9+. Sin embargo, la app iOS completa solo puede compilarse en macOS con Xcode.

## 🛠️ Próximos Pasos

1. [ ] Agregar clasificación de imágenes con Core ML para detectar tortas, decoraciones
2. [ ] Implementar detección de memes usando Vision + heurísticas
3. [ ] Agregar widget de iOS para "En este día"
4. [ ] Soporte para carpetas compartidas de iCloud
5. [ ] Exportar momentos como álbumes de Fotos

## 📄 Licencia

Este proyecto es para uso personal de Sebastián. Para uso comercial, contactar al autor.

---

**Desarrollado con ❤️ en Swift y SwiftUI**
