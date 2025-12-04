//
//  AppConfig.swift
//  PickAgent
//
//  Created by ChatGPT on 3/15/2025.
//

import Foundation

enum AppConfig {
    /// Base URL for all RunDaddy API requests.
    static let apiBaseURL: URL = {
//     return URL(string: "https://pickeragent.app/api")!
       return URL(string: "https://rundaddy.app/api")!
//      return URL(string: "http://localhost:3000/api")!
    }()
}
