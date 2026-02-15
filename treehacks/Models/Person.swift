//
//  Person.swift
//  treehacks
//

import UIKit

struct Person: Identifiable {
    var id: String
    var name: String
    var relationship: String
    var notes: String
    var phoneNumber: String
    /// Multiple face embeddings (one per reference photo) for better recognition.
    var faceEmbeddings: [[Float]]
    var referencePhotos: [UIImage]

    /// Convert to a codable payload for persistence (drops referencePhotos).
    func toPayload() -> PersonPayload {
        PersonPayload(
            id: id,
            name: name,
            relationship: relationship,
            notes: notes,
            phoneNumber: phoneNumber,
            faceEmbeddings: faceEmbeddings,
            referenceImageFile: nil,
            referenceImageData: nil,
            referenceImageName: nil
        )
    }
}

struct PersonPayload: Codable {
    var id: String
    var name: String
    var relationship: String
    var notes: String
    var phoneNumber: String?
    /// Multiple face embeddings (one per reference photo).
    var faceEmbeddings: [[Float]]
    var referenceImageFile: String?
    var referenceImageData: String?
    var referenceImageName: String?
}

extension PersonPayload {
    /// Convert to an in-memory Person (without reference photo resolution).
    func toPerson() -> Person {
        Person(
            id: id,
            name: name,
            relationship: relationship,
            notes: notes,
            phoneNumber: phoneNumber ?? "",
            faceEmbeddings: faceEmbeddings,
            referencePhotos: []
        )
    }
}

enum PersonLoader {
    static func loadFromBundle(filename: String?) -> [Person] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        guard let payloads = try? decoder.decode([PersonPayload].self, from: data) else {
            return []
        }
        return payloads.map { payload in
            var photos: [UIImage] = []
            if let file = payload.referenceImageFile {
                if let img = Self.loadImage(fromFile: file) {
                    photos.append(img)
                }
            }
            if let base64 = payload.referenceImageData,
               let data = Data(base64Encoded: base64),
               let img = UIImage(data: data) {
                photos.append(img)
            }
            if let name = payload.referenceImageName, !name.isEmpty,
               let img = UIImage(named: name) {
                photos.append(img)
            }
            return Person(
                id: payload.id,
                name: payload.name,
                relationship: payload.relationship,
                notes: payload.notes,
                phoneNumber: payload.phoneNumber ?? "",
                faceEmbeddings: payload.faceEmbeddings,
                referencePhotos: photos
            )
        }
    }

    private static func loadImage(fromFile file: String) -> UIImage? {
        let subdir: String?
        let filename: String
        if let slash = file.firstIndex(of: "/") {
            subdir = String(file[..<slash])
            filename = String(file[file.index(after: slash)...])
        } else {
            subdir = nil
            filename = file
        }
        let name: String
        let ext: String?
        if let lastDot = filename.lastIndex(of: "."), lastDot != filename.startIndex {
            name = String(filename[..<lastDot])
            ext = String(filename[filename.index(after: lastDot)...])
        } else {
            name = filename
            ext = nil
        }
        let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdir)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
        if let url = url, let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return nil
    }
}
