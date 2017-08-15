/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import NotificationCenter
import Storage
import Shared
import SnapKit
import XCGLogger

private let log = Logger.browserLogger

//You apparently can't extend anything other than UIViewController
//in a Today Widget without losing full functionality.
@objc (TodayBookmarkViewController)
class TodayBookmarkViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, NCWidgetProviding {
    fileprivate var tableView: UITableView
    fileprivate var bookmarks = [Site]()
    fileprivate let BookmarkCellIdentifier = "BookmarkIdentifier"
    fileprivate let noBookmarksString = "You haven't bookmarked \nanything yet."
    fileprivate var bookmarkCount: Int
    fileprivate let widgetHeight = 110 //This is Apple's default, and this cannot be changed.
    fileprivate var compactBookmarkCount: Int //Number of bookmarks shown initially (Before "Show More")
    fileprivate var bookmarkCellHeight: CGFloat //Depends on # of bookmarks, as height is divided
    fileprivate var tableHeight: CGFloat
    
    init() {
        //Gather the bookmark data
        let profile = BrowserProfile(localName:"profile")
        bookmarks = (profile.recommendations.getRecentBookmarks(5).value.successValue?.asArray())!
        profile.shutdown() //Close the profile
        
        bookmarkCount = bookmarks.count >= 5 ? 5 : bookmarks.count
        compactBookmarkCount = bookmarkCount <= 3 ? bookmarkCount : 3
        bookmarkCellHeight = bookmarkCount <= 0 ? CGFloat(widgetHeight) : CGFloat(widgetHeight/compactBookmarkCount)
        tableHeight = bookmarkCount <= 0 ? CGFloat(bookmarkCellHeight) : bookmarkCellHeight * CGFloat(bookmarkCount)
        self.tableView = UITableView(frame: .zero)
        
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        //Adds "Show more/Show less" functionality. Widgets have a default NCWidgetDisplayMode.compact height of 110 pixels that cannot be changed, but the NCWidgetDisplayMode.expanded height can be changed to anything.
        if bookmarkCount > 3 {
            if #available(iOS 10.0, *) {
                self.extensionContext?.widgetLargestAvailableDisplayMode = NCWidgetDisplayMode.expanded
            } else {
                // Fallback on earlier versions
            }
        }
        tableView.delegate = self
        tableView.dataSource = self
        tableView.frame = CGRect(x: 0, y: 0, width: view.bounds.width - 16, height: tableHeight)
        self.view.addSubview(self.tableView)
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return bookmarkCount <= 0 ? 1 : bookmarkCount
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return bookmarkCellHeight
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: BookmarkCellIdentifier)
        if cell == nil {
            let cellStyle = bookmarkCount <= 0 ? UITableViewCellStyle.default : UITableViewCellStyle.subtitle
            cell = UITableViewCell(style: cellStyle, reuseIdentifier: BookmarkCellIdentifier)
        }

        switch bookmarkCount {
        case 0: //No bookmarks. Show one non-interactive cell with text.
            cell?.selectionStyle = .none
            cell?.textLabel?.text = noBookmarksString
            cell?.textLabel?.numberOfLines = 0
            cell?.textLabel?.lineBreakMode = .byWordWrapping
            cell?.textLabel?.textAlignment = .center
            return cell!
        case 1: //One bookmark. Because widget height must be 110, it looks really funky. Include the URL as a detailTextLabel to make the space look less empty.
            cell?.textLabel?.text = bookmarks[indexPath.row].title
            cell?.detailTextLabel?.text = bookmarks[indexPath.row].url
        default:
            if bookmarks[indexPath.row].title.isEmpty {
                cell?.textLabel?.text = bookmarks[indexPath.row].url
            } else {
                cell?.textLabel?.text = bookmarks[indexPath.row].title
            }
        }
        //Filler image
        cell?.imageView?.image = UIImage(named: "favicon.png")
        //Setting the cell favicon. UIImageViewExtensions/FaviconFetcher can't be accessed by extensions afaik.(?)
        let currentBookmarkURL = bookmarks[indexPath.row]
        if let url = currentBookmarkURL.icon?.url.asURL {
            URLSession.shared.dataTask(with: url) { (data, response, error) in
                if error != nil {
                    print("Failed fetching image:", error ?? "Error")
                    return
                }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                    print("Not a proper HTTPURLResponse or statusCode")
                    return
                }
                DispatchQueue.main.async {
                    cell?.imageView?.image = UIImage(data: data!)
                    //Setting the size of the favicon. For some reason has to be here or else the icons resize upon selection.
                    let itemSize = CGSize(width: self.bookmarkCellHeight * 0.6, height: self.bookmarkCellHeight * 0.6)
                    UIGraphicsBeginImageContextWithOptions(itemSize, false, UIScreen.main.scale);
                    let imageRect = CGRect(x: 0.0, y: 0.0, width: itemSize.width, height: itemSize.height)
                    cell?.imageView?.image?.draw(in: imageRect)
                    cell?.imageView?.image? = UIGraphicsGetImageFromCurrentImageContext()!;
                    cell?.imageView?.layer.cornerRadius = self.bookmarkCount >= 2 ? CGFloat(4) : CGFloat(8)
                    UIGraphicsEndImageContext();
                }
            }.resume()
        }
        return cell!
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if bookmarkCount > 0 {
            tableView.deselectRow(at: indexPath as IndexPath, animated: false)
            let encodedString = bookmarks[indexPath.row].url.escape()
            openContainingApp("?url=\(encodedString)")
        }
    }
    //Opening a link
    fileprivate var scheme: String {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "MozInternalURLScheme") as? String else {
            // Something went wrong/weird, but we should fallback to the public one.
            return "firefox"
        }
        return string
    }
    
    fileprivate func openContainingApp(_ urlSuffix: String = "") {
        let urlString = "\(scheme)://open-url\(urlSuffix)"
        self.extensionContext?.open(URL(string: urlString)!) { success in
            log.info("Extension opened containing app: \(success)")
        }
    }
    //Enabling "Show More"/"Show Less" in widget
    @available(iOS 10.0, *)
    func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
        let expanded = activeDisplayMode == NCWidgetDisplayMode.expanded
        preferredContentSize = expanded ? CGSize(width: maxSize.width, height: bookmarkCellHeight * CGFloat(bookmarkCount)) : CGSize(width: maxSize.width, height: bookmarkCellHeight * 3)
        
    }
}

