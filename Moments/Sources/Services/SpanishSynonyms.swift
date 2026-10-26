// SpanishSynonyms.swift
// Mapeo de etiquetas de Vision a sinónimos en español

import Foundation

struct SpanishSynonyms {
    
    // Mapping from English Vision labels to Spanish equivalents
    static let labelMappings: [String: [String]] = [
        // Animals - Animales
        "dog": ["perro", "cachorro", "can", "mascota"],
        "cat": ["gato", "gatito", "felino", "mascota"],
        "bird": ["pájaro", "ave", "pajarito"],
        "horse": ["caballo", "yegua", "potro", "equino"],
        "cow": ["vaca", "toro", "ganado", "bovino"],
        "sheep": ["oveja", "cordero", "borrego"],
        "fish": ["pez", "pescado"],
        "butterfly": ["mariposa"],
        "insect": ["insecto", "bicho"],
        "elephant": ["elefante"],
        "bear": ["oso"],
        "lion": ["león"],
        "tiger": ["tigre"],
        "monkey": ["mono", "simio"],
        "rabbit": ["conejo", "liebre"],
        "duck": ["pato"],
        "chicken": ["pollo", "gallina"],
        
        // Nature - Naturaleza
        "beach": ["playa", "costa", "mar", "arena"],
        "mountain": ["montaña", "monte", "cerro", "cordillera"],
        "forest": ["bosque", "selva", "arboleda"],
        "tree": ["árbol", "arbolito"],
        "flower": ["flor", "flores", "florecita"],
        "plant": ["planta", "vegetal"],
        "grass": ["pasto", "césped", "hierba"],
        "lake": ["lago", "laguna"],
        "river": ["río", "arroyo"],
        "ocean": ["océano", "mar"],
        "sky": ["cielo"],
        "cloud": ["nube", "nubes"],
        "sun": ["sol"],
        "moon": ["luna"],
        "star": ["estrella"],
        "sunset": ["atardecer", "puesta de sol", "ocaso"],
        "sunrise": ["amanecer", "alba"],
        "snow": ["nieve", "nevado"],
        "rain": ["lluvia"],
        "waterfall": ["cascada", "catarata"],
        "desert": ["desierto"],
        "island": ["isla"],
        
        // People - Personas
        "person": ["persona", "gente"],
        "people": ["personas", "gente"],
        "man": ["hombre", "varón", "señor"],
        "woman": ["mujer", "señora", "dama"],
        "boy": ["niño", "chico", "nene"],
        "girl": ["niña", "chica", "nena"],
        "baby": ["bebé", "bebe", "bebito"],
        "child": ["niño", "niña", "chico", "chica"],
        "family": ["familia"],
        "couple": ["pareja"],
        "group": ["grupo"],
        "crowd": ["multitud", "muchedumbre"],
        "face": ["cara", "rostro"],
        "portrait": ["retrato", "portrait"],
        "selfie": ["selfie", "autorretrato", "foto propia"],
        
        // Food - Comida
        "food": ["comida", "alimento"],
        "fruit": ["fruta", "frutas"],
        "vegetable": ["verdura", "vegetal", "hortaliza"],
        "meat": ["carne"],
        "bread": ["pan"],
        "cake": ["torta", "pastel", "bizcocho"],
        "pizza": ["pizza"],
        "burger": ["hamburguesa"],
        "sandwich": ["sándwich", "sandwich", "emparedado"],
        "salad": ["ensalada"],
        "soup": ["sopa", "caldo"],
        "pasta": ["pasta", "fideos"],
        "rice": ["arroz"],
        "coffee": ["café"],
        "tea": ["té"],
        "wine": ["vino"],
        "beer": ["cerveza"],
        "ice cream": ["helado"],
        "chocolate": ["chocolate"],
        "apple": ["manzana"],
        "banana": ["banana", "plátano"],
        "orange": ["naranja"],
        "strawberry": ["frutilla", "fresa"],
        
        // Places - Lugares
        "city": ["ciudad", "urbe"],
        "building": ["edificio", "construcción"],
        "house": ["casa", "hogar", "vivienda"],
        "street": ["calle", "avenida"],
        "bridge": ["puente"],
        "tower": ["torre"],
        "church": ["iglesia", "templo", "catedral"],
        "museum": ["museo"],
        "restaurant": ["restaurante", "restorán"],
        "cafe": ["café", "cafetería"],
        "bar": ["bar"],
        "hotel": ["hotel"],
        "airport": ["aeropuerto"],
        "station": ["estación"],
        "park": ["parque", "plaza"],
        "garden": ["jardín"],
        "pool": ["piscina", "pileta"],
        "stadium": ["estadio"],
        "school": ["escuela", "colegio"],
        "hospital": ["hospital"],
        "office": ["oficina"],
        "store": ["tienda", "negocio", "local"],
        "market": ["mercado", "feria"],
        "mall": ["shopping", "centro comercial"],
        
        // Transportation - Transporte
        "car": ["auto", "carro", "coche", "vehículo"],
        "bus": ["colectivo", "bus", "ómnibus", "micro"],
        "train": ["tren", "ferrocarril"],
        "plane": ["avión", "aeronave"],
        "boat": ["barco", "bote", "lancha"],
        "ship": ["barco", "buque", "navío"],
        "bicycle": ["bicicleta", "bici"],
        "motorcycle": ["moto", "motocicleta"],
        "truck": ["camión"],
        "taxi": ["taxi"],
        "subway": ["subte", "metro"],
        
        // Activities - Actividades
        "sport": ["deporte"],
        "soccer": ["fútbol", "futbol"],
        "basketball": ["básquet", "baloncesto"],
        "tennis": ["tenis"],
        "swimming": ["natación", "nadar"],
        "running": ["correr", "carrera"],
        "hiking": ["caminata", "senderismo", "trekking"],
        "camping": ["camping", "acampar"],
        "fishing": ["pesca", "pescar"],
        "dancing": ["baile", "bailar", "danza"],
        "cooking": ["cocina", "cocinar"],
        "reading": ["lectura", "leer"],
        "music": ["música"],
        "concert": ["concierto", "recital"],
        "party": ["fiesta", "celebración"],
        "wedding": ["boda", "casamiento", "matrimonio"],
        "birthday": ["cumpleaños", "cumple"],
        "christmas": ["navidad", "navideño"],
        "holiday": ["vacaciones", "feriado"],
        "travel": ["viaje", "viajar"],
        
        // Objects - Objetos
        "phone": ["teléfono", "celular", "móvil"],
        "computer": ["computadora", "ordenador", "pc"],
        "laptop": ["notebook", "laptop", "portátil"],
        "tablet": ["tablet", "tableta"],
        "camera": ["cámara"],
        "book": ["libro"],
        "pen": ["lapicera", "bolígrafo", "pluma"],
        "chair": ["silla"],
        "table": ["mesa"],
        "bed": ["cama"],
        "sofa": ["sofá", "sillón"],
        "lamp": ["lámpara", "luz"],
        "clock": ["reloj"],
        "mirror": ["espejo"],
        "door": ["puerta"],
        "window": ["ventana"],
        "bag": ["bolso", "cartera", "mochila"],
        "clothes": ["ropa", "vestimenta"],
        "shoes": ["zapatos", "calzado"],
        "hat": ["sombrero", "gorro"],
        "glasses": ["anteojos", "gafas", "lentes"],
        "umbrella": ["paraguas"],
        "key": ["llave"],
        "money": ["dinero", "plata"],
        "gift": ["regalo", "obsequio"],
        "toy": ["juguete"],
        "ball": ["pelota", "balón"],
        
        // Documents - Documentos
        "document": ["documento", "papel"],
        "text": ["texto"],
        "receipt": ["recibo", "ticket", "factura", "comprobante"],
        "invoice": ["factura"],
        "ticket": ["ticket", "boleto", "entrada"],
        "card": ["tarjeta"],
        "letter": ["carta"],
        "sign": ["cartel", "señal"],
        "menu": ["menú", "carta"],
        "newspaper": ["diario", "periódico"],
        "magazine": ["revista"],
        "poster": ["poster", "afiche", "cartel"],
        "label": ["etiqueta"],
        "qr code": ["código qr", "qr"],
        "barcode": ["código de barras"],
        
        // Weather - Clima
        "sunny": ["soleado", "sol"],
        "cloudy": ["nublado", "nubes"],
        "rainy": ["lluvioso", "lluvia"],
        "snowy": ["nevado", "nieve"],
        "stormy": ["tormenta", "tormentoso"],
        "foggy": ["neblina", "niebla", "bruma"],
        
        // Time - Tiempo
        "day": ["día"],
        "night": ["noche", "nocturno"],
        "morning": ["mañana"],
        "afternoon": ["tarde"],
        "evening": ["atardecer", "anochecer"],
        
        // Art - Arte
        "painting": ["pintura", "cuadro"],
        "sculpture": ["escultura"],
        "drawing": ["dibujo"],
        "art": ["arte"],
        "mural": ["mural"],
        "graffiti": ["graffiti", "grafiti"],
        
        // Events - Eventos
        "celebration": ["celebración", "festejo"],
        "graduation": ["graduación", "egreso"],
        "ceremony": ["ceremonia"],
        "performance": ["actuación", "show", "espectáculo"],
        "exhibition": ["exposición", "muestra"],
    ]
    
    // Reverse mapping for search (Spanish to English)
    static let spanishToEnglish: [String: String] = {
        var mapping: [String: String] = [:]
        for (english, spanishTerms) in labelMappings {
            mapping[english] = english
            for spanish in spanishTerms {
                mapping[spanish.lowercased()] = english
            }
        }
        return mapping
    }()
    
    // Get all searchable terms for a given label
    static func searchTerms(for label: String) -> [String] {
        let lowercased = label.lowercased()
        var terms = [lowercased]
        
        if let synonyms = labelMappings[lowercased] {
            terms.append(contentsOf: synonyms)
        }
        
        return terms
    }
    
    // Check if a search query matches a label (including synonyms)
    static func matches(query: String, label: String) -> Bool {
        let queryLower = query.lowercased()
        let labelLower = label.lowercased()
        
        // Direct match
        if labelLower.contains(queryLower) {
            return true
        }
        
        // Check if query matches any Spanish synonym
        if let synonyms = labelMappings[labelLower] {
            for synonym in synonyms {
                if synonym.lowercased().contains(queryLower) {
                    return true
                }
            }
        }
        
        // Check if query is a Spanish term that maps to this label
        if let englishLabel = spanishToEnglish[queryLower], englishLabel == labelLower {
            return true
        }
        
        return false
    }
    
    // Convert a label to its Spanish equivalent (or return original)
    static func toSpanish(_ label: String) -> String {
        let lowercased = label.lowercased()
        if let synonyms = labelMappings[lowercased], let first = synonyms.first {
            return first
        }
        return label
    }
    
    // Convert a label string (pipe-separated) adding Spanish synonyms
    static func addSpanishSynonyms(to labels: String) -> String {
        let labelArray = labels.components(separatedBy: "|")
        var allTerms: Set<String> = Set(labelArray.map { $0.lowercased() })
        
        for label in labelArray {
            let terms = searchTerms(for: label)
            allTerms.formUnion(terms.map { $0.lowercased() })
        }
        
        return Array(allTerms).joined(separator: "|")
    }
}
