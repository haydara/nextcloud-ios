//
//  NCUtility.swift
//  Nextcloud
//
//  Created by Marino Faggiana on 25/06/18.
//  Copyright © 2018 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import SVGKit
import KTVHTTPCache
import NextcloudKit
import PDFKit
import Accelerate
import CoreMedia
import Queuer
import Photos
import JGProgressHUD

class NCUtility: NSObject {
    @objc static let shared: NCUtility = {
        let instance = NCUtility()
        return instance
    }()

    func setLayoutForView(key: String, serverUrl: String, layoutForView: NCGlobal.layoutForViewType) {

        let string =  layoutForView.layout + "|" + layoutForView.sort + "|" + "\(layoutForView.ascending)" + "|" + layoutForView.groupBy + "|" + "\(layoutForView.directoryOnTop)" + "|" + layoutForView.titleButtonHeader + "|" + "\(layoutForView.itemForLine)"
        var keyStore = key

        if serverUrl != "" {
            keyStore = serverUrl
        }

        UICKeyChainStore.setString(string, forKey: keyStore, service: NCGlobal.shared.serviceShareKeyChain)
    }

    func setLayoutForView(key: String, serverUrl: String, layout: String?) {

        var layoutForView: NCGlobal.layoutForViewType = NCUtility.shared.getLayoutForView(key: key, serverUrl: serverUrl)

        if let layout = layout {
            layoutForView.layout = layout
            setLayoutForView(key: key, serverUrl: serverUrl, layoutForView: layoutForView)
        }
    }

    func getLayoutForView(key: String, serverUrl: String, sort: String = "fileName", ascending: Bool = true, titleButtonHeader: String = "_sorted_by_name_a_z_") -> (NCGlobal.layoutForViewType) {

        var keyStore = key
        var layoutForView: NCGlobal.layoutForViewType = NCGlobal.layoutForViewType(layout: NCGlobal.shared.layoutList, sort: sort, ascending: ascending, groupBy: "none", directoryOnTop: true, titleButtonHeader: titleButtonHeader, itemForLine: 3)

        if serverUrl != "" {
            keyStore = serverUrl
        }

        guard let string = UICKeyChainStore.string(forKey: keyStore, service: NCGlobal.shared.serviceShareKeyChain) else {
            setLayoutForView(key: key, serverUrl: serverUrl, layoutForView: layoutForView)
            return layoutForView
        }

        let array = string.components(separatedBy: "|")
        if array.count >= 7 {
            // version 1
            layoutForView.layout = array[0]
            layoutForView.sort = array[1]
            layoutForView.ascending = NSString(string: array[2]).boolValue
            layoutForView.groupBy = array[3]
            layoutForView.directoryOnTop = NSString(string: array[4]).boolValue
            layoutForView.titleButtonHeader = array[5]
            layoutForView.itemForLine = Int(NSString(string: array[6]).intValue)
        }

        return layoutForView
    }

    func convertSVGtoPNGWriteToUserData(svgUrlString: String, fileName: String?, width: CGFloat?, rewrite: Bool, account: String, closure: @escaping (String?) -> Void) {

        var fileNamePNG = ""

        guard let svgUrlString = svgUrlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let iconURL = URL(string: svgUrlString) else {
            return closure(nil)
        }

        if let fileName = fileName {
            fileNamePNG = fileName
        } else {
            fileNamePNG = iconURL.deletingPathExtension().lastPathComponent + ".png"
        }

        let imageNamePath = CCUtility.getDirectoryUserData() + "/" + fileNamePNG

        if !FileManager.default.fileExists(atPath: imageNamePath) || rewrite == true {

            NextcloudKit.shared.downloadContent(serverUrl: iconURL.absoluteString) { _, data, error in

                if error == .success && data != nil {

                    if let image = UIImage(data: data!) {

                        var newImage: UIImage = image

                        if width != nil {

                            let ratio = image.size.height / image.size.width
                            let newSize = CGSize(width: width!, height: width! * ratio)

                            let renderFormat = UIGraphicsImageRendererFormat.default()
                            renderFormat.opaque = false
                            let renderer = UIGraphicsImageRenderer(size: CGSize(width: newSize.width, height: newSize.height), format: renderFormat)
                            newImage = renderer.image {
                                _ in
                                image.draw(in: CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height))
                            }
                        }

                        guard let pngImageData = newImage.pngData() else {
                            return closure(nil)
                        }

                        try? pngImageData.write(to: URL(fileURLWithPath: imageNamePath))

                        return closure(imageNamePath)

                    } else {

                        guard let svgImage: SVGKImage = SVGKImage(data: data) else {
                            return closure(nil)
                        }

                        if width != nil {
                            let scale = svgImage.size.height / svgImage.size.width
                            svgImage.size = CGSize(width: width!, height: width! * scale)
                        }

                        guard let image: UIImage = svgImage.uiImage else {
                            return closure(nil)
                        }
                        guard let pngImageData = image.pngData() else {
                            return closure(nil)
                        }

                        try? pngImageData.write(to: URL(fileURLWithPath: imageNamePath))

                        return closure(imageNamePath)
                    }
                } else {
                    return closure(nil)
                }
            }

        } else {
            return closure(imageNamePath)
        }
    }

    @objc func isSimulatorOrTestFlight() -> Bool {
        guard let path = Bundle.main.appStoreReceiptURL?.path else {
            return false
        }
        return path.contains("CoreSimulator") || path.contains("sandboxReceipt")
    }

    @objc func isSimulator() -> Bool {
        guard let path = Bundle.main.appStoreReceiptURL?.path else {
            return false
        }
        return path.contains("CoreSimulator")
    }

    @objc func isRichDocument(_ metadata: tableMetadata) -> Bool {

        guard let mimeType = CCUtility.getMimeType(metadata.fileNameView) else {
            return false
        }

        guard let richdocumentsMimetypes = NCManageDatabase.shared.getCapabilitiesServerArray(account: metadata.account, elements: NCElementsJSON.shared.capabilitiesRichdocumentsMimetypes) else {
            return false
        }

        // contentype
        for richdocumentMimetype: String in richdocumentsMimetypes {
            if richdocumentMimetype.contains(metadata.contentType) || metadata.contentType == "text/plain" {
                return true
            }
        }

        // mimetype
        if richdocumentsMimetypes.count > 0 && mimeType.components(separatedBy: ".").count > 2 {

            let mimeTypeArray = mimeType.components(separatedBy: ".")
            let mimeType = mimeTypeArray[mimeTypeArray.count - 2] + "." + mimeTypeArray[mimeTypeArray.count - 1]

            for richdocumentMimetype: String in richdocumentsMimetypes {
                if richdocumentMimetype.contains(mimeType) {
                    return true
                }
            }
        }

        return false
    }

    @objc func isDirectEditing(account: String, contentType: String) -> [String] {

        var editor: [String] = []

        guard let results = NCManageDatabase.shared.getDirectEditingEditors(account: account) else {
            return editor
        }

        for result: tableDirectEditingEditors in results {
            for mimetype in result.mimetypes {
                if mimetype == contentType {
                    editor.append(result.editor)
                }

                // HARDCODE
                // https://github.com/nextcloud/text/issues/913

                if mimetype == "text/markdown" && contentType == "text/x-markdown" {
                    editor.append(result.editor)
                }
                if contentType == "text/html" {
                    editor.append(result.editor)
                }
            }
            for mimetype in result.optionalMimetypes {
                if mimetype == contentType {
                    editor.append(result.editor)
                }
            }
        }

        // HARDCODE
        // if editor.count == 0 {
        //    editor.append(NCGlobal.shared.editorText)
        // }

        return Array(Set(editor))
    }

    @objc func removeAllSettings() {

        URLCache.shared.memoryCapacity = 0
        URLCache.shared.diskCapacity = 0
        KTVHTTPCache.cacheDeleteAllCaches()

        NCManageDatabase.shared.clearDatabase(account: nil, removeAccount: true)

        CCUtility.removeGroupDirectoryProviderStorage()
        CCUtility.removeGroupLibraryDirectory()

        CCUtility.removeDocumentsDirectory()
        CCUtility.removeTemporaryDirectory()

        CCUtility.createDirectoryStandard()

        CCUtility.deleteAllChainStore()
    }

    @objc func permissionsContainsString(_ metadataPermissions: String, permissions: String) -> Bool {

        for char in permissions {
            if metadataPermissions.contains(char) == false {
                return false
            }
        }
        return true
    }

    @objc func getCustomUserAgentNCText() -> String {
        let userAgent: String = CCUtility.getUserAgent()
        if UIDevice.current.userInterfaceIdiom == .phone {
            // NOTE: Hardcoded (May 2022)
            // Tested for iPhone SE (1st), iOS 12; iPhone Pro Max, iOS 15.4
            // 605.1.15 = WebKit build version
            // 15E148 = frozen iOS build number according to: https://chromestatus.com/feature/4558585463832576
            return userAgent + " " + "AppleWebKit/605.1.15 Mobile/15E148"
        } else {
            return userAgent
        }
    }

    @objc func getCustomUserAgentOnlyOffice() -> String {

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")!
        if UIDevice.current.userInterfaceIdiom == .pad {
            return "Mozilla/5.0 (iPad) Nextcloud-iOS/\(appVersion)"
        } else {
            return "Mozilla/5.0 (iPhone) Mobile Nextcloud-iOS/\(appVersion)"
        }
    }

    @objc func pdfThumbnail(url: URL, width: CGFloat = 240) -> UIImage? {

        guard let data = try? Data(contentsOf: url), let page = PDFDocument(data: data)?.page(at: 0) else {
            return nil
        }

        let pageSize = page.bounds(for: .mediaBox)
        let pdfScale = width / pageSize.width

        // Apply if you're displaying the thumbnail on screen
        let scale = UIScreen.main.scale * pdfScale
        let screenSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)

        return page.thumbnail(of: screenSize, for: .mediaBox)
    }

    @objc func isQuickLookDisplayable(metadata: tableMetadata) -> Bool {
        return true
    }

    @objc func ocIdToFileId(ocId: String?) -> String? {

        guard let ocId = ocId else { return nil }

        let items = ocId.components(separatedBy: "oc")
        if items.count < 2 { return nil }
        guard let intFileId = Int(items[0]) else { return nil }
        return String(intFileId)
    }

    func getUserStatus(userIcon: String?, userStatus: String?, userMessage: String?) -> (onlineStatus: UIImage?, statusMessage: String, descriptionMessage: String) {

        var onlineStatus: UIImage?
        var statusMessage: String = ""
        var descriptionMessage: String = ""
        var messageUserDefined: String = ""

        if userStatus?.lowercased() == "online" {
            onlineStatus = UIImage(named: "circle_fill")!.image(color: UIColor(red: 103.0/255.0, green: 176.0/255.0, blue: 134.0/255.0, alpha: 1.0), size: 50)
            messageUserDefined = NSLocalizedString("_online_", comment: "")
        }
        if userStatus?.lowercased() == "away" {
            onlineStatus = UIImage(named: "userStatusAway")!.image(color: UIColor(red: 233.0/255.0, green: 166.0/255.0, blue: 75.0/255.0, alpha: 1.0), size: 50)
            messageUserDefined = NSLocalizedString("_away_", comment: "")
        }
        if userStatus?.lowercased() == "dnd" {
            onlineStatus = UIImage(named: "userStatusDnd")?.resizeImage(size: CGSize(width: 100, height: 100), isAspectRation: false)
            messageUserDefined = NSLocalizedString("_dnd_", comment: "")
            descriptionMessage = NSLocalizedString("_dnd_description_", comment: "")
        }
        if userStatus?.lowercased() == "offline" || userStatus?.lowercased() == "invisible" {
            onlineStatus = UIImage(named: "userStatusOffline")!.image(color: .black, size: 50)
            messageUserDefined = NSLocalizedString("_invisible_", comment: "")
            descriptionMessage = NSLocalizedString("_invisible_description_", comment: "")
        }

        if let userIcon = userIcon {
            statusMessage = userIcon + " "
        }
        if let userMessage = userMessage {
            statusMessage += userMessage
        }
        statusMessage = statusMessage.trimmingCharacters(in: .whitespaces)
        if statusMessage == "" {
            statusMessage = messageUserDefined
        }

        return(onlineStatus, statusMessage, descriptionMessage)
    }

    // MARK: -

    func extractFiles(from metadata: tableMetadata, viewController: UIViewController?, hud: JGProgressHUD, completition: @escaping (_ metadatas: [tableMetadata]) -> Void) {

        let chunckSize = CCUtility.getChunkSize() * 1000000
        var metadatas: [tableMetadata] = []
        let metadataSource = tableMetadata.init(value: metadata)

        guard !metadata.isExtractFile else { return  completition([metadataSource]) }
        guard !metadataSource.assetLocalIdentifier.isEmpty else {
            let filePath = CCUtility.getDirectoryProviderStorageOcId(metadataSource.ocId, fileNameView: metadataSource.fileName)!
            metadataSource.size = NCUtilityFileSystem.shared.getFileSize(filePath: filePath)
            let results = NKCommon.shared.getInternalType(fileName: metadataSource.fileNameView, mimeType: metadataSource.contentType, directory: false)
            metadataSource.contentType = results.mimeType
            metadataSource.iconName = results.iconName
            metadataSource.classFile = results.classFile
            if let date = NCUtilityFileSystem.shared.getFileCreationDate(filePath: filePath) {
                metadataSource.creationDate = date
            }
            if let date = NCUtilityFileSystem.shared.getFileModificationDate(filePath: filePath) {
                metadataSource.date = date
            }
            metadataSource.chunk = chunckSize != 0 && metadata.size > chunckSize
            metadataSource.e2eEncrypted = CCUtility.isFolderEncrypted(metadata.serverUrl, e2eEncrypted: metadata.e2eEncrypted, account: metadata.account, urlBase: metadata.urlBase, userId: metadata.userId)
            metadataSource.isExtractFile = true
            if let metadata = NCManageDatabase.shared.addMetadata(metadataSource) {
                metadatas.append(metadata)
            }
            return completition(metadatas)
        }

        extractImageVideoFromAssetLocalIdentifier(metadata: metadataSource, modifyMetadataForUpload: true, viewController: viewController, hud: hud) { metadata, fileNamePath, returnError in
            if let metadata = metadata, let fileNamePath = fileNamePath, !returnError {
                metadatas.append(metadata)
                let toPath = CCUtility.getDirectoryProviderStorageOcId(metadata.ocId, fileNameView: metadata.fileNameView)!
                NCUtilityFileSystem.shared.moveFile(atPath: fileNamePath, toPath: toPath)
            } else {
                return completition(metadatas)
            }
            let fetchAssets = PHAsset.fetchAssets(withLocalIdentifiers: [metadataSource.assetLocalIdentifier], options: nil)
            if metadataSource.livePhoto, fetchAssets.count > 0  {
                NCUtility.shared.createMetadataLivePhotoFromMetadata(metadataSource, asset: fetchAssets.firstObject) { metadata in
                    if let metadata = metadata, let metadata = NCManageDatabase.shared.addMetadata(metadata) {
                        metadatas.append(metadata)
                    }
                    completition(metadatas)
                }
            } else {
                completition(metadatas)
            }
        }
    }

    func extractImageVideoFromAssetLocalIdentifier(metadata: tableMetadata, modifyMetadataForUpload: Bool, viewController: UIViewController?, hud: JGProgressHUD, completion: @escaping (_ metadata: tableMetadata?, _ fileNamePath: String?, _ error: Bool) -> ()) {

        var fileNamePath: String?
        let metadata = tableMetadata.init(value: metadata)
        let chunckSize = CCUtility.getChunkSize() * 1000000
        var compatibilityFormat: Bool = false

        func callCompletionWithError(_ error: Bool = true) {
            if error {
                completion(nil, nil, true)
            } else {
                var metadataReturn = metadata
                if modifyMetadataForUpload {
                    metadata.chunk = chunckSize != 0 && metadata.size > chunckSize
                    metadata.e2eEncrypted = CCUtility.isFolderEncrypted(metadata.serverUrl, e2eEncrypted: metadata.e2eEncrypted, account: metadata.account, urlBase: metadata.urlBase, userId: metadata.userId)
                    metadata.isExtractFile = true
                    if let metadata = NCManageDatabase.shared.addMetadata(metadata) {
                        metadataReturn = metadata
                    }
                }
                completion(metadataReturn, fileNamePath, error)
            }
        }

        let fetchAssets = PHAsset.fetchAssets(withLocalIdentifiers: [metadata.assetLocalIdentifier], options: nil)
        guard fetchAssets.count > 0, let asset = fetchAssets.firstObject, let extensionAsset = (asset.value(forKey: "filename") as? NSString)?.pathExtension.uppercased() else { return callCompletionWithError() }

        let creationDate = asset.creationDate ?? Date()
        let modificationDate = asset.modificationDate ?? Date()

        if asset.mediaType == PHAssetMediaType.image && (extensionAsset == "HEIC" || extensionAsset == "DNG") && CCUtility.getFormatCompatibility() {
            let fileName = (metadata.fileNameView as NSString).deletingPathExtension + ".jpg"
            metadata.contentType = "image/jpeg"
            metadata.ext = "jpg"
            fileNamePath = NSTemporaryDirectory() + fileName
            metadata.fileNameView = fileName
            if !metadata.e2eEncrypted {
                metadata.fileName = fileName
            }
            compatibilityFormat = true
        } else {
            fileNamePath = NSTemporaryDirectory() + metadata.fileNameView
        }

        guard let fileNamePath = fileNamePath else { return callCompletionWithError() }

        if asset.mediaType == PHAssetMediaType.image {

            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            if compatibilityFormat {
                options.deliveryMode = .opportunistic
            } else {
                options.deliveryMode = .highQualityFormat
            }
            options.isSynchronous = true
            if extensionAsset == "DNG" {
                options.version = PHImageRequestOptionsVersion.original
            }
            options.progressHandler = { (progress, error, stop, info) in
                print(progress)
                if error != nil { return callCompletionWithError() }
            }

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, dataUI, orientation, info in
                guard var data = data else { return callCompletionWithError() }
                if compatibilityFormat {
                    guard let ciImage = CIImage.init(data: data), let colorSpace = ciImage.colorSpace, let dataJPEG = CIContext().jpegRepresentation(of: ciImage, colorSpace: colorSpace) else { return callCompletionWithError() }
                    data = dataJPEG
                }
                NCUtilityFileSystem.shared.deleteFile(filePath: fileNamePath)
                do {
                    try data.write(to: URL(fileURLWithPath: fileNamePath), options: .atomic)
                } catch { return callCompletionWithError() }
                metadata.creationDate = creationDate as NSDate
                metadata.date = modificationDate as NSDate
                metadata.size = NCUtilityFileSystem.shared.getFileSize(filePath: fileNamePath)
                return callCompletionWithError(false)
            }

        } else if asset.mediaType == PHAssetMediaType.video {
            
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = PHVideoRequestOptionsVersion.current
            options.progressHandler = { (progress, error, stop, info) in
                print(progress)
                if error != nil { return callCompletionWithError() }
            }

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { asset, audioMix, info in
                if let asset = asset as? AVURLAsset {
                    NCUtilityFileSystem.shared.deleteFile(filePath: fileNamePath)
                    do {
                        try FileManager.default.copyItem(at: asset.url, to: URL(fileURLWithPath: fileNamePath))
                        metadata.creationDate = creationDate as NSDate
                        metadata.date = modificationDate as NSDate
                        metadata.size = NCUtilityFileSystem.shared.getFileSize(filePath: fileNamePath)
                        return callCompletionWithError(false)
                    } catch { return callCompletionWithError() }
                } else if let asset = asset as? AVComposition, asset.tracks.count > 1, let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality), let viewController = viewController {
                    DispatchQueue.main.async {
                        hud.indicatorView = JGProgressHUDRingIndicatorView()
                        if let indicatorView = hud.indicatorView as? JGProgressHUDRingIndicatorView {
                            indicatorView.ringWidth = 1.5
                        }
                        hud.textLabel.text = NSLocalizedString("_exporting_video_", comment: "")
                        hud.show(in: viewController.view)
                        hud.tapOnHUDViewBlock = { hud in
                            exporter.cancelExport()
                        }
                    }
                    exporter.outputURL = URL(fileURLWithPath: fileNamePath)
                    exporter.outputFileType = AVFileType.mp4
                    exporter.shouldOptimizeForNetworkUse = true
                    exporter.exportAsynchronously {
                        DispatchQueue.main.async { hud.dismiss() }
                        if exporter.status == .completed {
                            metadata.creationDate = creationDate as NSDate
                            metadata.date = modificationDate as NSDate
                            metadata.size = NCUtilityFileSystem.shared.getFileSize(filePath: fileNamePath)
                            return callCompletionWithError(false)
                        } else { return callCompletionWithError() }
                    }
                    while exporter.status == AVAssetExportSession.Status.exporting || exporter.status == AVAssetExportSession.Status.waiting {
                        hud.progress = exporter.progress
                    }
                } else {
                    return callCompletionWithError()
                }
            }
        } else {
            return callCompletionWithError()
        }
    }

    func createMetadataLivePhotoFromMetadata(_ metadata: tableMetadata, asset: PHAsset?, completion: @escaping (_ metadata: tableMetadata?) -> ()) {

        guard let asset = asset else { return completion(nil) }
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = PHImageRequestOptionsDeliveryMode.fastFormat
        options.isNetworkAccessAllowed = true
        let chunckSize = CCUtility.getChunkSize() * 1000000
        let e2eEncrypted = CCUtility.isFolderEncrypted(metadata.serverUrl, e2eEncrypted: metadata.e2eEncrypted, account: metadata.account, urlBase: metadata.urlBase, userId: metadata.userId)
        let ocId = NSUUID().uuidString
        let fileName = (metadata.fileName as NSString).deletingPathExtension + ".mov"
        let fileNamePath = CCUtility.getDirectoryProviderStorageOcId(ocId, fileNameView: fileName)!

        PHImageManager.default().requestLivePhoto(for: asset, targetSize: UIScreen.main.bounds.size, contentMode: PHImageContentMode.default, options: options) { livePhoto, info in
            guard let livePhoto = livePhoto else { return completion(nil) }
            var videoResource: PHAssetResource?
            for resource in PHAssetResource.assetResources(for: livePhoto) {
                if resource.type == PHAssetResourceType.pairedVideo {
                    videoResource = resource
                    break
                }
            }
            guard let videoResource = videoResource else { return completion(nil) }
            NCUtilityFileSystem.shared.deleteFile(filePath: fileNamePath)
            PHAssetResourceManager.default().writeData(for: videoResource, toFile: URL(fileURLWithPath: fileNamePath), options: nil) { error in
                if error != nil { return completion(nil) }
                let metadataLivePhoto = NCManageDatabase.shared.createMetadata(account: metadata.account, user: metadata.user, userId: metadata.userId, fileName: fileName, fileNameView: fileName, ocId: ocId, serverUrl: metadata.serverUrl, urlBase: metadata.urlBase, url: "", contentType: "", isLivePhoto: true)
                metadataLivePhoto.classFile = NKCommon.typeClassFile.video.rawValue
                metadataLivePhoto.e2eEncrypted = e2eEncrypted
                metadataLivePhoto.isExtractFile = true
                metadataLivePhoto.session = metadata.session
                metadataLivePhoto.sessionSelector = metadata.sessionSelector
                metadataLivePhoto.size = NCUtilityFileSystem.shared.getFileSize(filePath: fileNamePath)
                metadataLivePhoto.status = metadata.status
                metadataLivePhoto.chunk = chunckSize != 0 && metadata.size > chunckSize
                return completion(NCManageDatabase.shared.addMetadata(metadataLivePhoto))
            }
        }
    }

    func imageFromVideo(url: URL, at time: TimeInterval) -> UIImage? {

        let asset = AVURLAsset(url: url)
        let assetIG = AVAssetImageGenerator(asset: asset)

        assetIG.appliesPreferredTrackTransform = true
        assetIG.apertureMode = AVAssetImageGenerator.ApertureMode.encodedPixels

        let cmTime = CMTime(seconds: time, preferredTimescale: 60)
        let thumbnailImageRef: CGImage
        do {
            thumbnailImageRef = try assetIG.copyCGImage(at: cmTime, actualTime: nil)
        } catch let error {
            print("Error: \(error)")
            return nil
        }

        return UIImage(cgImage: thumbnailImageRef)
    }

    func imageFromVideo(url: URL, at time: TimeInterval, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global().async {

            let asset = AVURLAsset(url: url)
            let assetIG = AVAssetImageGenerator(asset: asset)

            assetIG.appliesPreferredTrackTransform = true
            assetIG.apertureMode = AVAssetImageGenerator.ApertureMode.encodedPixels

            let cmTime = CMTime(seconds: time, preferredTimescale: 60)
            let thumbnailImageRef: CGImage
            do {
                thumbnailImageRef = try assetIG.copyCGImage(at: cmTime, actualTime: nil)
            } catch let error {
                print("Error: \(error)")
                return completion(nil)
            }

            DispatchQueue.main.async {
                completion(UIImage(cgImage: thumbnailImageRef))
            }
        }
    }

    func createImageFrom(fileNameView: String, ocId: String, etag: String, classFile: String) {

        var originalImage, scaleImagePreview, scaleImageIcon: UIImage?

        let fileNamePath = CCUtility.getDirectoryProviderStorageOcId(ocId, fileNameView: fileNameView)!
        let fileNamePathPreview = CCUtility.getDirectoryProviderStoragePreviewOcId(ocId, etag: etag)!
        let fileNamePathIcon = CCUtility.getDirectoryProviderStorageIconOcId(ocId, etag: etag)!

        if CCUtility.fileProviderStorageSize(ocId, fileNameView: fileNameView) > 0 && FileManager().fileExists(atPath: fileNamePathPreview) && FileManager().fileExists(atPath: fileNamePathIcon) { return }
        if classFile != NKCommon.typeClassFile.image.rawValue && classFile != NKCommon.typeClassFile.video.rawValue { return }

        if classFile == NKCommon.typeClassFile.image.rawValue {

            originalImage = UIImage(contentsOfFile: fileNamePath)

            scaleImagePreview = originalImage?.resizeImage(size: CGSize(width: NCGlobal.shared.sizePreview, height: NCGlobal.shared.sizePreview))
            scaleImageIcon = originalImage?.resizeImage(size: CGSize(width: NCGlobal.shared.sizeIcon, height: NCGlobal.shared.sizeIcon))

            try? scaleImagePreview?.jpegData(compressionQuality: 0.7)?.write(to: URL(fileURLWithPath: fileNamePathPreview))
            try? scaleImageIcon?.jpegData(compressionQuality: 0.7)?.write(to: URL(fileURLWithPath: fileNamePathIcon))

        } else if classFile == NKCommon.typeClassFile.video.rawValue {

            let videoPath = NSTemporaryDirectory()+"tempvideo.mp4"
            NCUtilityFileSystem.shared.linkItem(atPath: fileNamePath, toPath: videoPath)

            originalImage = imageFromVideo(url: URL(fileURLWithPath: videoPath), at: 0)

            try? originalImage?.jpegData(compressionQuality: 0.7)?.write(to: URL(fileURLWithPath: fileNamePathPreview))
            try? originalImage?.jpegData(compressionQuality: 0.7)?.write(to: URL(fileURLWithPath: fileNamePathIcon))
        }
    }

    @objc func getVersionApp(withBuild: Bool = true) -> String {
        if let dictionary = Bundle.main.infoDictionary {
            if let version = dictionary["CFBundleShortVersionString"], let build = dictionary["CFBundleVersion"] {
                if withBuild {
                    return "\(version).\(build)"
                } else {
                    return "\(version)"
                }
            }
        }
        return ""
    }

    func loadImage(named imageName: String, color: UIColor = NCBrandColor.shared.gray, size: CGFloat = 50, symbolConfiguration: Any? = nil) -> UIImage {

        var image: UIImage?

        // see https://stackoverflow.com/questions/71764255
        let sfSymbolName = imageName.replacingOccurrences(of: "_", with: ".")
        if let symbolConfiguration = symbolConfiguration {
            image = UIImage(systemName: sfSymbolName, withConfiguration: symbolConfiguration as? UIImage.Configuration)?.withTintColor(color, renderingMode: .alwaysOriginal)
        } else {
            image = UIImage(systemName: sfSymbolName)?.withTintColor(color, renderingMode: .alwaysOriginal)
        }
        if image == nil {
            image = UIImage(named: imageName)?.image(color: color, size: size)
        }
        if let image = image {
            return image
        }

        return  UIImage(named: "file")!.image(color: color, size: size)
    }

    @objc func loadUserImage(for user: String, displayName: String?, userBaseUrl: NCUserBaseUrl) -> UIImage {

        let fileName = userBaseUrl.userBaseUrl + "-" + user + ".png"
        let localFilePath = String(CCUtility.getDirectoryUserData()) + "/" + fileName

        if let localImage = UIImage(contentsOfFile: localFilePath) {
            return createAvatar(image: localImage, size: 30)
        } else if let loadedAvatar = NCManageDatabase.shared.getImageAvatarLoaded(fileName: fileName) {
            return loadedAvatar
        } else if let displayName = displayName, !displayName.isEmpty, let avatarImg = createAvatar(displayName: displayName, size: 30) {
            return avatarImg
        } else { return getDefaultUserIcon() }
    }

    func getDefaultUserIcon() -> UIImage {
            
        let config = UIImage.SymbolConfiguration(pointSize: 30)
        return NCUtility.shared.loadImage(named: "person.crop.circle", symbolConfiguration: config)
    }

    @objc func createAvatar(image: UIImage, size: CGFloat) -> UIImage {

        var avatarImage = image
        let rect = CGRect(x: 0, y: 0, width: size, height: size)

        UIGraphicsBeginImageContextWithOptions(rect.size, false, 3.0)
        UIBezierPath(roundedRect: rect, cornerRadius: rect.size.height).addClip()
        avatarImage.draw(in: rect)
        avatarImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()

        return avatarImage
    }

    func createAvatar(displayName: String, size: CGFloat) -> UIImage? {
        guard let initials = displayName.uppercaseInitials else {
            return nil
        }
        let userColor = NCGlobal.shared.usernameToColor(displayName)
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        var avatarImage: UIImage?

        UIGraphicsBeginImageContextWithOptions(rect.size, false, 3.0)
        let context = UIGraphicsGetCurrentContext()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.size.height).addClip()
        context?.setFillColor(userColor)
        context?.fill(rect)
        let textStyle = NSMutableParagraphStyle()
        textStyle.alignment = NSTextAlignment.center
        let lineHeight = UIFont.systemFont(ofSize: UIFont.systemFontSize).pointSize
        NSString(string: initials)
            .draw(
                in: CGRect(x: 0, y: (size - lineHeight) / 2, width: size, height: lineHeight),
                withAttributes: [NSAttributedString.Key.paragraphStyle: textStyle])
        avatarImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return avatarImage
    }

    /*
    Facebook's comparison algorithm:
    */

    func compare(tolerance: Float, expected: Data, observed: Data) throws -> Bool {

        enum customError: Error {
            case unableToGetUIImageFromData
            case unableToGetCGImageFromData
            case unableToGetColorSpaceFromCGImage
            case imagesHasDifferentSizes
            case unableToInitializeContext
        }

        guard let expectedUIImage = UIImage(data: expected), let observedUIImage = UIImage(data: observed) else {
            throw customError.unableToGetUIImageFromData
        }
        guard let expectedCGImage = expectedUIImage.cgImage, let observedCGImage = observedUIImage.cgImage else {
            throw customError.unableToGetCGImageFromData
        }
        guard let expectedColorSpace = expectedCGImage.colorSpace, let observedColorSpace = observedCGImage.colorSpace else {
            throw customError.unableToGetColorSpaceFromCGImage
        }
        if expectedCGImage.width != observedCGImage.width || expectedCGImage.height != observedCGImage.height {
            throw customError.imagesHasDifferentSizes
        }
        let imageSize = CGSize(width: expectedCGImage.width, height: expectedCGImage.height)
        let numberOfPixels = Int(imageSize.width * imageSize.height)

        // Checking that our `UInt32` buffer has same number of bytes as image has.
        let bytesPerRow = min(expectedCGImage.bytesPerRow, observedCGImage.bytesPerRow)
        assert(MemoryLayout<UInt32>.stride == bytesPerRow / Int(imageSize.width))

        let expectedPixels = UnsafeMutablePointer<UInt32>.allocate(capacity: numberOfPixels)
        let observedPixels = UnsafeMutablePointer<UInt32>.allocate(capacity: numberOfPixels)

        let expectedPixelsRaw = UnsafeMutableRawPointer(expectedPixels)
        let observedPixelsRaw = UnsafeMutableRawPointer(observedPixels)

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let expectedContext = CGContext(data: expectedPixelsRaw, width: Int(imageSize.width), height: Int(imageSize.height),
                                              bitsPerComponent: expectedCGImage.bitsPerComponent, bytesPerRow: bytesPerRow,
                                              space: expectedColorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            expectedPixels.deallocate()
            observedPixels.deallocate()
            throw customError.unableToInitializeContext
        }
        guard let observedContext = CGContext(data: observedPixelsRaw, width: Int(imageSize.width), height: Int(imageSize.height),
                                              bitsPerComponent: observedCGImage.bitsPerComponent, bytesPerRow: bytesPerRow,
                                              space: observedColorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            expectedPixels.deallocate()
            observedPixels.deallocate()
            throw customError.unableToInitializeContext
        }

        expectedContext.draw(expectedCGImage, in: CGRect(origin: .zero, size: imageSize))
        observedContext.draw(observedCGImage, in: CGRect(origin: .zero, size: imageSize))

        let expectedBuffer = UnsafeBufferPointer(start: expectedPixels, count: numberOfPixels)
        let observedBuffer = UnsafeBufferPointer(start: observedPixels, count: numberOfPixels)

        var isEqual = true
        if tolerance == 0 {
            isEqual = expectedBuffer.elementsEqual(observedBuffer)
        } else {
            // Go through each pixel in turn and see if it is different
            var numDiffPixels = 0
            for pixel in 0 ..< numberOfPixels where expectedBuffer[pixel] != observedBuffer[pixel] {
                // If this pixel is different, increment the pixel diff count and see if we have hit our limit.
                numDiffPixels += 1
                let percentage = 100 * Float(numDiffPixels) / Float(numberOfPixels)
                if percentage > tolerance {
                    isEqual = false
                    break
                }
            }
        }

        expectedPixels.deallocate()
        observedPixels.deallocate()

        return isEqual
    }

    func stringFromTime(_ time: CMTime) -> String {

        let interval = Int(CMTimeGetSeconds(time))

        let seconds = interval % 60
        let minutes = (interval / 60) % 60
        let hours = (interval / 3600)

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    func colorNavigationController(_ navigationController: UINavigationController?, backgroundColor: UIColor, titleColor: UIColor, tintColor: UIColor?, withoutShadow: Bool) {

        let appearance = UINavigationBarAppearance()
        appearance.titleTextAttributes = [.foregroundColor: titleColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: titleColor]

        if withoutShadow {
            appearance.shadowColor = .clear
            appearance.shadowImage = UIImage()
        }

        if let tintColor = tintColor {
            navigationController?.navigationBar.tintColor = tintColor
        }

        navigationController?.view.backgroundColor = backgroundColor
        navigationController?.navigationBar.barTintColor = titleColor
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
    }

    func getEncondingDataType(data: Data) -> String.Encoding? {
        if let _ = String(data: data, encoding: .utf8) {
            return .utf8
        }
        if let _ = String(data: data, encoding: .ascii) {
            return .ascii
        }
        if let _ = String(data: data, encoding: .isoLatin1) {
            return .isoLatin1
        }
        if let _ = String(data: data, encoding: .isoLatin2) {
            return .isoLatin2
        }
        if let _ = String(data: data, encoding: .windowsCP1250) {
            return .windowsCP1250
        }
        if let _ = String(data: data, encoding: .windowsCP1251) {
            return .windowsCP1251
        }
        if let _ = String(data: data, encoding: .windowsCP1252) {
            return .windowsCP1252
        }
        if let _ = String(data: data, encoding: .windowsCP1253) {
            return .windowsCP1253
        }
        if let _ = String(data: data, encoding: .windowsCP1254) {
            return .windowsCP1254
        }
        if let _ = String(data: data, encoding: .macOSRoman) {
            return .macOSRoman
        }
        if let _ = String(data: data, encoding: .japaneseEUC) {
            return .japaneseEUC
        }
        if let _ = String(data: data, encoding: .nextstep) {
            return .nextstep
        }
        if let _ = String(data: data, encoding: .nonLossyASCII) {
            return .nonLossyASCII
        }
        if let _ = String(data: data, encoding: .shiftJIS) {
            return .shiftJIS
        }
        if let _ = String(data: data, encoding: .symbol) {
            return .symbol
        }
        if let _ = String(data: data, encoding: .unicode) {
            return .unicode
        }
        if let _ = String(data: data, encoding: .utf16) {
            return .utf16
        }
        if let _ = String(data: data, encoding: .utf16BigEndian) {
            return .utf16BigEndian
        }
        if let _ = String(data: data, encoding: .utf16LittleEndian) {
            return .utf16LittleEndian
        }
        if let _ = String(data: data, encoding: .utf32) {
            return .utf32
        }
        if let _ = String(data: data, encoding: .utf32BigEndian) {
            return .utf32BigEndian
        }
        if let _ = String(data: data, encoding: .utf32LittleEndian) {
            return .utf32LittleEndian
        }
        return nil
    }

    func SYSTEM_VERSION_LESS_THAN(version: String) -> Bool {
        return UIDevice.current.systemVersion.compare(version,
         options: NSString.CompareOptions.numeric) == ComparisonResult.orderedAscending
    }

    func getAvatarFromIconUrl(metadata: tableMetadata) -> String? {

        var ownerId: String?
        if metadata.iconUrl.contains("http") && metadata.iconUrl.contains("avatar") {
            let splitIconUrl = metadata.iconUrl.components(separatedBy: "/")
            var found:Bool = false
            for item in splitIconUrl {
                if found {
                    ownerId = item
                    break
                }
                if item == "avatar" { found = true}
            }
        }
        return ownerId
    }

    // https://stackoverflow.com/questions/25471114/how-to-validate-an-e-mail-address-in-swift
    func isValidEmail(_ email: String) -> Bool {
        
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
    
    func createFilePreviewImage(ocId: String, etag: String, fileNameView: String, classFile: String, status: Int, createPreviewMedia: Bool) -> UIImage? {

        var imagePreview: UIImage?
        let filePath = CCUtility.getDirectoryProviderStorageOcId(ocId, fileNameView: fileNameView)!
        let iconImagePath = CCUtility.getDirectoryProviderStorageIconOcId(ocId, etag: etag)!

        if FileManager().fileExists(atPath: iconImagePath) {
            imagePreview = UIImage(contentsOfFile: iconImagePath)
        } else if !createPreviewMedia {
            return nil
        } else if createPreviewMedia && status >= NCGlobal.shared.metadataStatusNormal && classFile == NKCommon.typeClassFile.image.rawValue && FileManager().fileExists(atPath: filePath) {
            if let image = UIImage(contentsOfFile: filePath), let image = image.resizeImage(size: CGSize(width: NCGlobal.shared.sizeIcon, height: NCGlobal.shared.sizeIcon)), let data = image.jpegData(compressionQuality: 0.5) {
                do {
                    try data.write(to: URL.init(fileURLWithPath: iconImagePath), options: .atomic)
                    imagePreview = image
                } catch { }
            }
        } else if createPreviewMedia && status >= NCGlobal.shared.metadataStatusNormal && classFile == NKCommon.typeClassFile.video.rawValue && FileManager().fileExists(atPath: filePath) {
            if let image = NCUtility.shared.imageFromVideo(url: URL(fileURLWithPath: filePath), at: 0), let image = image.resizeImage(size: CGSize(width: NCGlobal.shared.sizeIcon, height: NCGlobal.shared.sizeIcon)), let data = image.jpegData(compressionQuality: 0.5) {
                do {
                    try data.write(to: URL.init(fileURLWithPath: iconImagePath), options: .atomic)
                    imagePreview = image
                } catch { }
            }
        }

        return imagePreview
    }

    @discardableResult
    func convertDataToImage(data: Data?, size:CGSize, fileNameToWrite: String?) -> UIImage? {

        guard let data = data else { return nil }
        var returnImage: UIImage?

        if let image = UIImage(data: data), let image = image.resizeImage(size: size) {
            returnImage = image
        } else if let image = SVGKImage(data: data) {
            image.size = size
            returnImage = image.uiImage
        } else {
            print("error")
        }
        if let fileName = fileNameToWrite, let image = returnImage {
            do {
                let fileNamePath: String = CCUtility.getDirectoryUserData() + "/" + fileName + ".png"
                try image.pngData()?.write(to: URL(fileURLWithPath: fileNamePath), options: .atomic)
            } catch { }
        }
        return returnImage
    }
}
