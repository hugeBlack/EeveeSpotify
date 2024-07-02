import Foundation
import Orion

class SPTDataLoaderServiceHook: ClassHook<NSObject> {
    
    static let targetName = "SPTDataLoaderService"
    
    // orion:new
    func shouldModify(_ url: URL) -> Bool {
        let isModifyingCustomizeResponse = UserDefaults.patchType == .requests
        return url.isLyrics || (url.isCustomize && isModifyingCustomizeResponse)
    }
    
    func URLSession(
        _ session: URLSession,
        task: URLSessionDataTask,
        didCompleteWithError error: Error?
    ) {
        guard
            let request = task.currentRequest,
            let url = request.url
        else {
            return
        }
        
        if error == nil && shouldModify(url) {
            
            if let buffer = URLSessionHelper.shared.obtainData(for: url) {
                
                if url.isLyrics {
                    
                    do {
                        orig.URLSession(
                            session,
                            dataTask: task,
                            didReceiveData: try getCurrentTrackLyricsData(
                                originalLyrics: try? Lyrics(serializedData: buffer)
                            )
                        )
                        
                        orig.URLSession(session, task: task, didCompleteWithError: nil)
                    }
                    catch {
                        orig.URLSession(session, task: task, didCompleteWithError: error)
                    }
                    
                    return
                }
                
                do {
                    var customizeMessage = try CustomizeMessage(serializedData: buffer)
                    modifyRemoteConfiguration(&customizeMessage.response)
                    
                    orig.URLSession(
                        session,
                        dataTask: task,
                        didReceiveData: try customizeMessage.serializedData()
                    )
                    
                    orig.URLSession(session, task: task, didCompleteWithError: nil)

                    NSLog("[EeveeSpotify] Modified customize data")
                    return
                }
                catch {
                    NSLog("[EeveeSpotify] Unable to modify customize data: \(error)")
                }
            }
        }
        
        orig.URLSession(session, task: task, didCompleteWithError: error)
        
    }

    func URLSession(
        _ session: URLSession,
        dataTask task: URLSessionDataTask,
        didReceiveResponse response: HTTPURLResponse,
        completionHandler handler: Any
    ) {
        let url = response.url!
        
        if url.isLyrics, response.statusCode != 200 {

            let okResponse = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "2.0",
                headerFields: [:]
            )!
            
            do {
                let lyricsData = try getCurrentTrackLyricsData()
                
                orig.URLSession(
                    session,
                    dataTask: task,
                    didReceiveResponse: okResponse,
                    completionHandler: handler
                )
                
                orig.URLSession(session, dataTask: task, didReceiveData: lyricsData)
                orig.URLSession(session, task: task, didCompleteWithError: nil)

                return
            }
            catch {
                NSLog("[EeveeSpotify] Unable to load lyrics: \(error)")
                orig.URLSession(session, task: task, didCompleteWithError: error)
                
                return
            }
        }

        orig.URLSession(
            session,
            dataTask: task,
            didReceiveResponse: response,
            completionHandler: handler
        )
    }

    func URLSession(
        _ session: URLSession,
        dataTask task: URLSessionDataTask,
        didReceiveData data: Data
    ) {
        guard
            let request = task.currentRequest,
            let url = request.url
        else {
            return
        }

        if shouldModify(url) {
            URLSessionHelper.shared.setOrAppend(data, for: url)
            return
        }

        orig.URLSession(session, dataTask: task, didReceiveData: data)
    }
}
