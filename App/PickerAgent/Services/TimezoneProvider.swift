//
//  TimezoneProvider.swift
//  PickAgent
//
//  Created by ChatGPT on 11/25/2025.
//

import Foundation

class TimezoneProvider {
    static var shared = TimezoneProvider()
    
    private var _companyTimeZoneIdentifier: String?
    
    var companyTimeZoneIdentifier: String {
        return _companyTimeZoneIdentifier ?? TimeZone.current.identifier
    }
    
    func setCompanyTimeZone(_ identifier: String) {
        _companyTimeZoneIdentifier = identifier
    }
    
    func resetToDeviceTimezone() {
        _companyTimeZoneIdentifier = nil
    }
}