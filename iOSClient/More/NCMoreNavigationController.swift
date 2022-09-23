//
//  NCMoreNavigationController.swift
//  Nextcloud
//
//  Created by Marino Faggiana on 17/10/2020.
//  Copyright © 2020 Marino Faggiana. All rights reserved.
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

class NCMoreNavigationController: UINavigationController {

    // MARK: - View Life Cycle

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        let standardAppearance = UINavigationBarAppearance()

        standardAppearance.configureWithOpaqueBackground()
        standardAppearance.largeTitleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.label]
        standardAppearance.configureWithOpaqueBackground()
        standardAppearance.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.label]
        standardAppearance.backgroundColor = .systemGroupedBackground

        standardAppearance.shadowColor = .clear
        standardAppearance.shadowImage = UIImage()

        let scrollEdgeAppearance = UINavigationBarAppearance()
        
        scrollEdgeAppearance.backgroundColor = .systemGroupedBackground

        navigationBar.scrollEdgeAppearance = standardAppearance
        navigationBar.standardAppearance = scrollEdgeAppearance
        navigationBar.tintColor = .systemBlue
    }
}
