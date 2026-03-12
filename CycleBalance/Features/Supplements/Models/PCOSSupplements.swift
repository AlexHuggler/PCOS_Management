import Foundation

struct PCOSSupplement: Identifiable {
    let id = UUID()
    let name: String
    let defaultDosageMg: Double
    let description: String
}

enum PCOSSupplements {
    static let catalog: [PCOSSupplement] = [
        PCOSSupplement(name: "Inositol", defaultDosageMg: 4000, description: "Supports insulin sensitivity and cycle regularity."),
        PCOSSupplement(name: "Vitamin D", defaultDosageMg: 2000, description: "Supports hormone and immune function."),
        PCOSSupplement(name: "Omega-3", defaultDosageMg: 1000, description: "Supports heart health and inflammation balance."),
        PCOSSupplement(name: "Berberine", defaultDosageMg: 500, description: "Supports healthy glucose metabolism."),
        PCOSSupplement(name: "NAC", defaultDosageMg: 600, description: "Supports antioxidant and ovulatory health."),
        PCOSSupplement(name: "Zinc", defaultDosageMg: 30, description: "Supports skin and hormone health."),
        PCOSSupplement(name: "Magnesium", defaultDosageMg: 400, description: "Supports sleep, muscle, and stress response."),
        PCOSSupplement(name: "Spearmint Tea", defaultDosageMg: 0, description: "Herbal option commonly used for androgen support."),
        PCOSSupplement(name: "Folate", defaultDosageMg: 400, description: "Supports cell growth and preconception health."),
        PCOSSupplement(name: "Chromium", defaultDosageMg: 200, description: "Supports insulin response and energy metabolism."),
    ]
}
