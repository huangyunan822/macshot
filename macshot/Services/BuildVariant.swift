enum BuildVariant {
    #if CORPORATE
    static let isCorporate = true
    static let displayName = "macshot Corporate"
    #else
    static let isCorporate = false
    static let displayName = "macshot"
    #endif
}
