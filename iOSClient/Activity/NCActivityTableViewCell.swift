//
//  NCActivityCollectionViewCell.swift
//  Nextcloud
//
//  Created by Henrik Storch on 17/01/2019.
//  Copyright © 2021. All rights reserved.
//
//  Author Henrik Storch <henrik.storch@nextcloud.com>
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

import Foundation
import NextcloudKit
import FloatingPanel
import JGProgressHUD

class NCActivityCollectionViewCell: UICollectionViewCell {

    @IBOutlet weak var imageView: UIImageView!

    var fileId = ""

    override func awakeFromNib() {
        super.awakeFromNib()
    }
}

class NCActivityTableViewCell: UITableViewCell, NCCellProtocol {

    private let appDelegate = UIApplication.shared.delegate as! AppDelegate

    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var icon: UIImageView!
    @IBOutlet weak var avatar: UIImageView!
    @IBOutlet weak var subject: UILabel!
    @IBOutlet weak var subjectTrailingConstraint: NSLayoutConstraint!
    @IBOutlet weak var collectionViewHeightConstraint: NSLayoutConstraint!

    private var user: String = ""

    var idActivity: Int = 0
    var activityPreviews: [tableActivityPreview] = []
    var didSelectItemEnable: Bool = true
    var viewController: UIViewController?

    var fileAvatarImageView: UIImageView? {
        get { return avatar }
    }
    var fileUser: String? {
        get { return user }
        set { user = newValue ?? "" }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        collectionView.delegate = self
        collectionView.dataSource = self
        let avatarRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapAvatarImage))
        avatar.addGestureRecognizer(avatarRecognizer)
    }

    @objc func tapAvatarImage() {
        guard let fileUser = fileUser else { return }
        viewController?.showProfileMenu(userId: fileUser)
    }
}

// MARK: - Collection View

extension NCActivityTableViewCell: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

        // Select not permitted
        if !didSelectItemEnable {
            return
        }

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "collectionCell", for: indexPath) as? NCActivityCollectionViewCell

        let activityPreview = activityPreviews[indexPath.row]

        if activityPreview.view == "trashbin" {

            var responder: UIResponder? = collectionView
            while !(responder is UIViewController) {
                responder = responder?.next
                if responder == nil {
                    break
                }
            }
            if (responder as? UIViewController)!.navigationController != nil {
                if let viewController = UIStoryboard(name: "NCTrash", bundle: nil).instantiateInitialViewController() as? NCTrash {
                    if let result = NCManageDatabase.shared.getTrashItem(fileId: String(activityPreview.fileId), account: activityPreview.account) {
                        viewController.blinkFileId = result.fileId
                        viewController.trashPath = result.filePath
                        (responder as? UIViewController)!.navigationController?.pushViewController(viewController, animated: true)
                    } else {
                        let error = NKError(errorCode: NCGlobal.shared.errorInternalError, errorDescription: "_trash_file_not_found_")
                        NCContentPresenter.shared.showError(error: error)
                    }
                }
            }

            return
        }

        if activityPreview.view == NCGlobal.shared.appName && activityPreview.mimeType != "dir" {

            guard let activitySubjectRich = NCManageDatabase.shared.getActivitySubjectRich(account: activityPreview.account, idActivity: activityPreview.idActivity, id: String(activityPreview.fileId)) else {
                return
            }

            if let metadata = NCManageDatabase.shared.getMetadata(predicate: NSPredicate(format: "fileId == %@", activitySubjectRich.id)) {
                if let filePath = CCUtility.getDirectoryProviderStorageOcId(metadata.ocId, fileNameView: metadata.fileNameView) {
                    do {
                        let attr = try FileManager.default.attributesOfItem(atPath: filePath)
                        let fileSize = attr[FileAttributeKey.size] as! UInt64
                        if fileSize > 0 {
                            if let viewController = self.viewController {
                                NCViewer.shared.view(viewController: viewController, metadata: metadata, metadatas: [metadata], imageIcon: cell?.imageView.image)
                            }
                            return
                        }
                    } catch {
                        print("Error: \(error)")
                    }
                }
            }

            let hud = JGProgressHUD()
            hud.indicatorView = JGProgressHUDRingIndicatorView()
            if let indicatorView = hud.indicatorView as? JGProgressHUDRingIndicatorView {
                indicatorView.ringWidth = 1.5
            }
            guard let view = appDelegate.window?.rootViewController?.view else { return }
            hud.show(in: view)

            NextcloudKit.shared.getFileFromFileId(fileId: String(activityPreview.fileId)) { account, file, data, error in
                if let file = file {

                    let metadata = NCManageDatabase.shared.convertNCFileToMetadata(file, isEncrypted: file.e2eEncrypted, account: account)
                    NCManageDatabase.shared.addMetadata(metadata)

                    let serverUrlFileName = metadata.serverUrl + "/" + metadata.fileName
                    let fileNameLocalPath = CCUtility.getDirectoryProviderStorageOcId(metadata.ocId, fileNameView: metadata.fileNameView)!

                    NextcloudKit.shared.download(serverUrlFileName: serverUrlFileName, fileNameLocalPath: fileNameLocalPath, requestHandler: { _ in
                    }, taskHandler: { _ in
                    }, progressHandler: { progress in
                        hud.progress = Float(progress.fractionCompleted)
                    }) { account, _, _, _, _, _, error in
                        hud.dismiss()
                        if account == self.appDelegate.account && error == .success {
                            NCManageDatabase.shared.addLocalFile(metadata: metadata)
                            if let viewController = self.viewController {
                                NCViewer.shared.view(viewController: viewController, metadata: metadata, metadatas: [metadata], imageIcon: cell?.imageView.image)
                            }
                        }
                    }
                } else if error != .success {
                    hud.dismiss()
                    NCContentPresenter.shared.showError(error: error)
                }
            }
        }
    }
}

extension NCActivityTableViewCell: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let results = activityPreviews.unique { $0.fileId }
        return results.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell: NCActivityCollectionViewCell = collectionView.dequeueReusableCell(withReuseIdentifier: "collectionCell", for: indexPath) as! NCActivityCollectionViewCell

        cell.imageView.image = nil

        let activityPreview = activityPreviews[indexPath.row]
        let fileId = String(activityPreview.fileId)

        // Trashbin
        if activityPreview.view == "trashbin" {

            let source = activityPreview.source

            NCUtility.shared.convertSVGtoPNGWriteToUserData(svgUrlString: source, fileName: nil, width: 100, rewrite: false, account: appDelegate.account) { imageNamePath in
                if imageNamePath != nil {
                    if let image = UIImage(contentsOfFile: imageNamePath!) {
                        cell.imageView.image = image
                    }
                } else {
                     cell.imageView.image = UIImage(named: "file_photo")
                }
            }

        } else {

            if activityPreview.isMimeTypeIcon {

                let source = activityPreview.source

                NCUtility.shared.convertSVGtoPNGWriteToUserData(svgUrlString: source, fileName: nil, width: 100, rewrite: false, account: appDelegate.account) { imageNamePath in
                    if imageNamePath != nil {
                        if let image = UIImage(contentsOfFile: imageNamePath!) {
                            cell.imageView.image = image
                        }
                    } else {
                        cell.imageView.image = UIImage(named: "file_photo")
                    }
                }

            } else {

                if let activitySubjectRich = NCManageDatabase.shared.getActivitySubjectRich(account: activityPreview.account, idActivity: idActivity, id: fileId) {

                    let fileNamePath = CCUtility.getDirectoryUserData() + "/" + activitySubjectRich.name

                    if FileManager.default.fileExists(atPath: fileNamePath) {

                        if let image = UIImage(contentsOfFile: fileNamePath) {
                            cell.imageView.image = image
                        }

                    } else {

                        NCOperationQueue.shared.downloadThumbnailActivity(fileNamePathOrFileId: activityPreview.source, fileNamePreviewLocalPath: fileNamePath, fileId: fileId, cell: cell, collectionView: collectionView)
                    }
                }
            }
        }

        return cell
    }

}

extension NCActivityTableViewCell: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 50, height: 50)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 20
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
    }
}
