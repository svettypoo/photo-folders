import Foundation

/// Hand-made word lists that sit next to the on-device models.
enum Vocabulary {
    /// Words people type that carry no meaning for a photo search.
    static let stopwords: Set<String> = [
        "a", "an", "the", "of", "in", "on", "at", "from", "with", "and", "or", "my", "mine", "our", "ours",
        "photo", "photos", "picture", "pictures", "pic", "pics", "image", "images", "shot", "shots", "snap",
        "snaps", "show", "find", "search", "get", "give", "all", "some", "that", "this", "these", "those",
        "was", "were", "is", "are", "be", "been", "taken", "took", "where", "when", "what", "which", "who",
        "i", "we", "us", "you", "your", "it", "its", "there", "any", "for", "to", "by", "during", "near",
        "like", "looking", "having", "has", "have", "had", "lots", "lot", "many", "bunch", "few", "one",
        "into", "onto", "about", "around", "since", "while", "me", "please", "can", "could", "would",
        "just", "only", "very", "really", "also", "then", "than", "them", "they", "their", "his", "her",
        "him", "she", "he", "time", "times", "ones", "stuff", "thing", "things", "kind", "sort", "type",
    ]

    /// Everyday words -> labels the vision model uses. Only labels that exist in the index are used.
    static let synonyms: [String: [String]] = [
        "puppy": ["dog", "puppy", "canine"], "pup": ["dog", "puppy"], "doggy": ["dog"], "doggo": ["dog"],
        "hound": ["dog"], "pooch": ["dog"],
        "kitten": ["cat", "kitten", "feline"], "kitty": ["cat", "kitten"], "kittens": ["cat", "kitten"],
        "meal": ["food", "meal", "dish"], "dinner": ["food", "meal", "dish", "table"], "lunch": ["food", "meal", "sandwich"],
        "breakfast": ["food", "breakfast", "egg", "pancake", "coffee"], "dish": ["food", "dish"], "eating": ["food", "meal"],
        "restaurant": ["food", "restaurant", "table", "meal"], "snack": ["food", "snack"], "dessert": ["dessert", "cake", "ice cream"],
        "ocean": ["sea", "ocean", "beach", "shore", "water"], "seaside": ["shore", "beach", "sea"], "coast": ["shore", "beach", "sea", "cliff"],
        "kid": ["child", "baby", "people"], "kids": ["child", "baby", "people"], "toddler": ["child", "baby"],
        "infant": ["baby"], "newborn": ["baby"], "son": ["child", "people"], "daughter": ["child", "people"],
        "selfie": ["people", "selfie", "portrait"], "friends": ["people", "group photo"], "family": ["people", "group photo", "child"],
        "person": ["people", "adult"], "human": ["people", "adult"], "face": ["people", "portrait"], "faces": ["people"],
        "crowd": ["crowd", "people", "group photo"], "group": ["group photo", "people", "crowd"],
        "vehicle": ["car", "vehicle", "automobile", "truck"], "automobile": ["car", "automobile", "vehicle"], "truck": ["truck", "car", "vehicle"],
        "bike": ["bicycle", "bike", "motorcycle"], "motorbike": ["motorcycle"],
        "receipt": ["receipt", "document", "paper", "text"], "invoice": ["document", "receipt", "paper", "text"], "bill": ["receipt", "document", "text"],
        "paperwork": ["document", "paper", "text"], "paper": ["document", "paper"], "letter": ["document", "paper", "text"],
        "form": ["document", "text"], "notes": ["document", "text", "handwriting"], "note": ["document", "text", "handwriting"],
        "screen": ["screenshot"], "screenshot": ["screenshot"], "screengrab": ["screenshot"], "screencap": ["screenshot"],
        "sunset": ["sunset sunrise", "sunset", "sky"], "sunrise": ["sunset sunrise", "sunrise", "sky"], "dusk": ["sunset sunrise"], "dawn": ["sunset sunrise"],
        "xmas": ["christmas tree", "christmas decoration", "christmas"], "christmas": ["christmas tree", "christmas decoration", "christmas"],
        "birthday": ["birthday cake", "cake", "candle", "party", "balloon"], "party": ["party", "celebration", "balloon", "people"],
        "hike": ["hiking", "mountain", "forest", "trail"], "hiking": ["hiking", "mountain", "forest", "trail"], "trail": ["trail", "forest", "path"],
        "lake": ["lake", "water", "shore"], "river": ["river", "water", "stream"],
        "blossom": ["flower", "blossom"], "bloom": ["flower", "blossom"], "flowers": ["flower"], "garden": ["garden", "flower", "plant", "grass"],
        "drink": ["beverage", "drink"], "drinks": ["beverage", "drink", "alcohol"], "cocktail": ["cocktail", "beverage", "alcohol"],
        "beer": ["beer", "beverage", "alcohol"], "wine": ["wine", "beverage", "alcohol"], "coffee": ["coffee", "beverage", "cup"],
        "wedding": ["wedding", "bride", "wedding dress"], "plane": ["airplane", "aircraft"], "airplane": ["airplane", "aircraft"],
        "flight": ["airplane", "aircraft", "airport"], "airport": ["airport", "airplane"],
        "city": ["cityscape", "city", "skyscraper", "building", "street"], "downtown": ["cityscape", "skyscraper", "street"],
        "street": ["street", "road", "city"], "house": ["house", "building", "home"], "home": ["house", "room", "interior room"],
        "pool": ["swimming pool", "pool"], "swimming": ["swimming", "swimming pool", "water"], "gym": ["gym", "exercise"],
        "workout": ["gym", "exercise"], "favourite": ["favorite"], "favorites": ["favorite"], "favourites": ["favorite"],
        "fav": ["favorite"], "faves": ["favorite"], "liked": ["favorite"], "best": ["favorite"], "hearted": ["favorite"],
        "pano": ["panorama"], "night": ["night sky", "night"], "stars": ["night sky", "star"], "moon": ["moon", "night sky"],
        "snowy": ["snow"], "skiing": ["skiing", "snow", "ski"], "ski": ["skiing", "ski", "snow"], "winter": ["snow"],
        "rainy": ["rain", "cloudy"], "clouds": ["cloudy", "cloud", "sky"], "sky": ["sky", "blue sky"],
        "mountains": ["mountain"], "hills": ["hill", "mountain"], "woods": ["forest", "tree"], "trees": ["tree", "forest"],
        "car": ["car", "automobile", "vehicle"], "cars": ["car", "automobile", "vehicle"], "boat": ["boat", "watercraft", "ship"],
        "concert": ["concert", "stage", "crowd"], "show": ["concert", "stage"], "game": ["sport", "stadium"],
        "soccer": ["soccer", "sport", "ball"], "football": ["football", "sport", "ball"], "hockey": ["hockey", "ice hockey", "sport"],
        "fish": ["fish", "aquarium"], "horse": ["horse", "equine"], "bird": ["bird"], "birds": ["bird"],
        "baby": ["baby", "child"], "food": ["food"], "text": ["text", "document"], "document": ["document", "text"],
        "documents": ["document", "text"], "sign": ["sign", "signboard", "text"], "menu": ["menu", "text", "document"],
        "art": ["art", "painting", "drawing"], "painting": ["painting", "art"], "drawing": ["drawing", "art"],
        "computer": ["computer", "laptop", "screen"], "laptop": ["laptop", "computer"], "phone": ["phone", "cell phone"],
    ]

    /// Labels too vague to name a folder or to split photos by.
    static let genericLabels: Set<String> = [
        "structure", "material", "textile", "wood processed", "raw glass", "indoor", "outdoor",
        "machine", "consumer electronics", "container", "equipment", "tool", "liquid", "conveyance",
    ]

    /// Correct but bookish labels: fine for search, weaker as a folder name ("Canine" -> prefer "Dog").
    static let technicalLabels: Set<String> = [
        "canine", "feline", "mammal", "ungulates", "equine", "bovine", "rodent", "reptile", "utensil",
        "tableware", "conveyance", "land", "liquid", "water body", "celestial body", "portal", "decoration",
        "people", "adult", "consumer electronics", "raptor", "invertebrate", "insect", "arachnid",
    ]

    /// Labels that suggest the photo contains readable words, so it is worth reading them.
    static let textHints: [String] = [
        "document", "text", "receipt", "paper", "handwriting", "menu", "poster", "sign", "book", "letter",
        "whiteboard", "blackboard", "screenshot", "card", "calendar", "newspaper", "magazine", "map",
        "label", "ticket", "note", "chart", "diagram", "screen", "monitor", "computer", "laptop", "billboard",
    ]

    /// Small picture shown on each folder, picked from the folder's words.
    static func symbol(for keywords: [String]) -> String {
        let table: [(String, String)] = [
            ("screenshot", "iphone"), ("dog", "pawprint.fill"), ("puppy", "pawprint.fill"), ("canine", "pawprint.fill"),
            ("cat", "cat.fill"), ("feline", "cat.fill"), ("bird", "bird.fill"), ("fish", "fish.fill"), ("animal", "pawprint"),
            ("food", "fork.knife"), ("dish", "fork.knife"), ("meal", "fork.knife"), ("dessert", "birthday.cake.fill"),
            ("cake", "birthday.cake.fill"), ("drink", "wineglass.fill"), ("beverage", "cup.and.saucer.fill"), ("coffee", "cup.and.saucer.fill"),
            ("sunset", "sun.horizon.fill"), ("sunrise", "sun.horizon.fill"), ("beach", "beach.umbrella.fill"), ("shore", "beach.umbrella.fill"),
            ("sea", "water.waves"), ("ocean", "water.waves"), ("water", "drop.fill"), ("lake", "water.waves"), ("mountain", "mountain.2.fill"),
            ("snow", "snowflake"), ("ski", "figure.skiing.downhill"), ("sky", "cloud.sun.fill"), ("cloud", "cloud.fill"),
            ("night", "moon.stars.fill"), ("car", "car.fill"), ("vehicle", "car.fill"), ("automobile", "car.fill"), ("truck", "truck.box.fill"),
            ("bicycle", "bicycle"), ("airplane", "airplane"), ("aircraft", "airplane"), ("boat", "sailboat.fill"),
            ("document", "doc.text.fill"), ("text", "doc.text.fill"), ("receipt", "receipt"), ("paper", "doc.fill"),
            ("people", "person.2.fill"), ("adult", "person.fill"), ("child", "figure.and.child.holdinghands"), ("baby", "figure.and.child.holdinghands"),
            ("portrait", "person.crop.square.fill"), ("group", "person.3.fill"), ("crowd", "person.3.fill"),
            ("flower", "camera.macro"), ("plant", "leaf.fill"), ("tree", "tree.fill"), ("forest", "tree.fill"), ("grass", "leaf.fill"),
            ("building", "building.2.fill"), ("city", "building.2.fill"), ("skyscraper", "building.2.fill"), ("house", "house.fill"),
            ("room", "sofa.fill"), ("interior", "sofa.fill"), ("furniture", "sofa.fill"), ("kitchen", "refrigerator.fill"),
            ("christmas", "gift.fill"), ("party", "party.popper.fill"), ("sport", "sportscourt.fill"), ("ball", "soccerball"),
            ("computer", "laptopcomputer"), ("laptop", "laptopcomputer"), ("phone", "iphone"), ("art", "paintpalette.fill"),
            ("painting", "paintpalette.fill"), ("clothing", "tshirt.fill"), ("shoe", "shoe.fill"), ("book", "book.fill"),
            ("music", "music.note"), ("concert", "music.mic"),
        ]
        for keyword in keywords {
            for (needle, symbol) in table where keyword.contains(needle) { return symbol }
        }
        return "folder.fill"
    }
}
