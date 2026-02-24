import Foundation
import SwiftData

@Model
final class HairPhotoEntry {
    var id: UUID
    var date: Date
    var photoType: HairPhotoType
    @Attribute(.externalStorage) var photoData: Data
    var notes: String?
    var analysisResult: String?

    init(
        id: UUID = UUID(),
        date: Date,
        photoType: HairPhotoType,
        photoData: Data,
        notes: String? = nil,
        analysisResult: String? = nil
    ) {
        self.id = id
        self.date = date
        self.photoType = photoType
        self.photoData = photoData
        self.notes = notes
        self.analysisResult = analysisResult
    }
}
