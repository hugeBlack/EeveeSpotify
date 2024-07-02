import Orion
import SwiftUI

class SPTPlayerTrackHook: ClassHook<NSObject> {

    static let targetName = "SPTPlayerTrack"

    func metadata() -> [String:String] {
        var meta = orig.metadata()
        
        meta["has_lyrics"] = "true"
        return meta
    }
}

class EncoreButtonHook: ClassHook<UIButton> {

    static let targetName = "_TtC12EncoreMobileP33_6EF3A3C098E69FB1E331877B69ACBF8512EncoreButton"

    func intrinsicContentSize() -> CGSize {

        if target.accessibilityIdentifier == "Components.UI.LyricsHeader.ReportButton", 
            UserDefaults.lyricsSource != .musixmatch {
            target.isEnabled = false
        }

        return orig.intrinsicContentSize()
    }
}

//

private var lastLyricsError: LyricsError? = nil

private var hasShownRestrictedPopUp = false
private var hasShownUnauthorizedPopUp = false

//

class LyricsOnlyViewControllerHook: ClassHook<UIViewController> {
    
    static var targetName: String {
        if #available(iOS 15.0, *) {
            "Lyrics_NPVCommunicatorImpl.LyricsOnlyViewController"
        } else {
            "Lyrics_CoreImpl.LyricsOnlyViewController"
        }
    }

    func viewDidLoad() {
        
        orig.viewDidLoad()
        
        if !UserDefaults.fallbackReasons {
            return
        }
        
        guard
            let lyricsHeaderViewController = target.parent?.children.first
        else {
            return
        }
        
        //
        
        let lyricsLabel: UIView?
        
        if #available(iOS 15.0, *) {
            lyricsLabel = lyricsHeaderViewController.view.subviews.first
        } else {
            lyricsLabel = lyricsHeaderViewController.view.subviews.first?.subviews.first
        }
        
        guard let lyricsLabel = lyricsLabel else {
            return
        }
        
        //

        let encoreLabel = Dynamic.convert(lyricsLabel, to: SPTEncoreLabel.self)
        
        var text = [
            encoreLabel.text().firstObject
        ]
        
        if let description = lastLyricsError?.description {
            
            let attributes = Dynamic.SPTEncoreAttributes
                .alloc(interface: SPTEncoreAttributes.self)
                .`init`({ attributes in
                    attributes.setForegroundColor(.white.withAlphaComponent(0.5))
                })
            
            let typeStyle = type(
                of: Dynamic.SPTEncoreTypeStyle.alloc(interface: SPTEncoreTypeStyle.self)
            ).bodyMediumBold()
            
            text.append(
                Dynamic.SPTEncoreAttributedString.alloc(interface: SPTEncoreAttributedString.self)
                    .initWithString(
                        "\nFallback: \(description)",
                        typeStyle: typeStyle,
                        attributes: attributes
                    )
            )
            
            if #unavailable(iOS 15.0) {
                encoreLabel.setNumberOfLines(2)
            }
        }

        encoreLabel.setText(text as NSArray)
    }
}

func getCurrentTrackLyricsData(originalLyrics: Lyrics? = nil) throws -> Data {
    
    guard let track = HookedInstances.currentTrack else {
        throw LyricsError.NoCurrentTrack
    }
    
    var source = UserDefaults.lyricsSource
    
    let plainLyrics: PlainLyrics?

    let metadata = track.metadata()
    let duration = Int(metadata["duration"]!)!

    do {
        plainLyrics = try LyricsRepository.getLyrics(
            title: track.trackTitle(), 
            artist: track.artistsString(),
            spotifyTrackId: track.URI().spt_trackIdentifier(),
            duration: duration,
            source: source
        )
        
        lastLyricsError = nil
    }
    
    catch let error as LyricsError {
        
        lastLyricsError = error
        
        switch error {
            
        case .InvalidMusixmatchToken:
            
            if !hasShownUnauthorizedPopUp {
                
                PopUpHelper.showPopUp(
                    delayed: false,
                    message: "The tweak is unable to load lyrics from Musixmatch due to Unauthorized error. Please check or update your Musixmatch token. If you use an iPad, you should get the token from the Musixmatch app for iPad.",
                    buttonText: "OK"
                )
                
                hasShownUnauthorizedPopUp.toggle()
            }
        
        case .MusixmatchRestricted:
            
            if !hasShownRestrictedPopUp {
                
                PopUpHelper.showPopUp(
                    delayed: false,
                    message: "The tweak is unable to load lyrics from Musixmatch because they are restricted. It's likely a copyright issue due to the US IP address, so you should change it if you're in the US or use a VPN.",
                    buttonText: "OK"
                )
                
                hasShownRestrictedPopUp.toggle()
            }
            
        default:
            break
        }
        
        if source == .genius || !UserDefaults.geniusFallback {
            throw error
        }
        
        NSLog("[EeveeSpotify] Unable to load lyrics from \(source): \(error), trying Genius as fallback")
        source = .genius
        
        plainLyrics = try LyricsRepository.getLyrics(
                title: track.trackTitle(), 
                artist: track.artistsString(),
                spotifyTrackId: track.URI().spt_trackIdentifier(),
                duration: duration,
                source: source
        )
    }

    let lyrics = try Lyrics.with {
        $0.colors = getLyricsColors()
        $0.data = try LyricsHelper.composeLyricsData(plainLyrics!, source: source)
    }

    return try lyrics.serializedData()
    
    func getLyricsColors() -> LyricsColors {
        
        let lyricsColorsSettings = UserDefaults.lyricsColors
        
        if lyricsColorsSettings.displayOriginalColors, let originalLyrics = originalLyrics {
            return originalLyrics.colors
        }
        
        return LyricsColors.with {
            $0.backgroundColor = lyricsColorsSettings.useStaticColor
                ? Color(hex: lyricsColorsSettings.staticColor).uInt32
                : Color(hex: track.extractedColorHex())
                    .normalized(lyricsColorsSettings.normalizationFactor)
                    .uInt32
            $0.lineColor = Color.black.uInt32
            $0.activeLineColor = Color.white.uInt32
        }
    }
}
