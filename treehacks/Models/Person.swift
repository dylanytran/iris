//
//  Person.swift
//  treehacks
//
//  Created by Dylan Tran on 2/14/26.
//

import SwiftData
import SwiftUI

@Model
final class Person {
    var name: String
    var relationship: String
    var notes: String
    @Attribute(.externalStorage) var faceImageData: Data?
    var faceDescriptorData: Data? // Serialized [Float] landmark feature vector
    var dateAdded: Date

    init(
        name: String,
        relationship: String = "",
        notes: String = "",
        faceImageData: Data? = nil,
        faceDescriptorData: Data? = nil
    ) {
        self.name = name
        self.relationship = relationship
        self.notes = notes
        self.faceImageData = faceImageData
        self.faceDescriptorData = faceDescriptorData
        self.dateAdded = Date()
    }

    // MARK: - Face Descriptor Helpers

    var faceDescriptor: [Float]? {
        get {
            guard let data = faceDescriptorData else { return nil }
            return data.withUnsafeBytes { pointer in
                Array(pointer.bindMemory(to: Float.self))
            }
        }
        set {
            guard let values = newValue else {
                faceDescriptorData = nil
                return
            }
            faceDescriptorData = values.withUnsafeBytes { Data($0) }
        }
    }

    var faceImage: UIImage? {
        guard let data = faceImageData else { return nil }
        return UIImage(data: data)
    }
}
