//
//  GreatCoursesViewController.swift
//  Great-Courses-Extractor
//
//  Created by Erik Larsen on 6/14/14.
//  Copyright (c) 2014 Erik Larsen. All rights reserved.
//
//  MIT LICENSE
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the
//  "Software"), to deal in the Software without restriction, including
//  without limitation the rights to use, copy, modify, merge, publish,
//  distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to
//  the following conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
//  LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
//  OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
//  WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


import Foundation
import Cocoa
import ScriptingBridge

class GreatCoursesViewController: NSViewController
{

    var htmlData : NSData?
    var url: NSURL?
    var lectures: Lecture[] = []
    var seriesTitle: NSString = ""
    var lecturer = ""
    var serialQueue = dispatch_queue_create("com.elarsen.sublerQ", DISPATCH_QUEUE_SERIAL)


    @IBOutlet var urlTextField : NSTextField
    @IBOutlet var window : NSWindow

    @IBAction func scrape(sender : AnyObject)
    {
        self.lectures.removeAll(keepCapacity: true)
        self.url = NSURL(string: self.urlTextField.stringValue)
        dispatch_async(serialQueue,
        {
            self.htmlData = NSData(contentsOfURL: self.url)

            dispatch_async(dispatch_get_main_queue(),
            {
                self.parse()
                self.window.title = self.seriesTitle

            })
        })

    }

    @IBAction func addToFiles(sender : NSButton)
    {
        let openPanel = NSOpenPanel()
        openPanel.allowedFileTypes = ["m4v", "mp4", "M4V", "MP4"]
        openPanel.canSelectHiddenExtension = true
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false;
        openPanel.allowsMultipleSelection = true;
        openPanel.beginSheetModalForWindow(window, completionHandler: {result in
            if result == NSFileHandlingPanelOKButton
            {
                for var i = 0; i < openPanel.URLs.count; i++
                {
                    self.metadataTask(openPanel.URLs[i] as NSURL, index: i)
                }

            }
        })

    }


    func metadataTask(fileURL: NSURL, index: Int)
    {
        dispatch_async(serialQueue, {
            let task = NSTask()
            let pipe = NSPipe()
            let file = pipe.fileHandleForReading

            task.launchPath = NSBundle.mainBundle().pathForResource("AtomicParsley", ofType: nil)

            // problem with Swift and array initalizers (crash, beta 1) is why this is like this
            var tmpArgs = [fileURL.path]
            tmpArgs += "--stik"
            tmpArgs += "value=10"
            tmpArgs += "--title"
            tmpArgs += self.lectures[index].title
            tmpArgs += "--TVShowName"
            tmpArgs += self.seriesTitle
            tmpArgs += "--TVSeasonNum"
            tmpArgs += "1"
            tmpArgs += "--description"
            tmpArgs += self.lectures[index].lectureDescription
            tmpArgs += "--longdesc"
            tmpArgs += self.lectures[index].lectureDescription
            tmpArgs += "--tracknum"
            tmpArgs += String(index + 1) + "/" + String(self.lectures.count)
            tmpArgs += "--TVEpisodeNum"
            tmpArgs += String(index + 1)
            tmpArgs += "--TVEpisode"
            tmpArgs += String(index + 101)
            tmpArgs += "--artist"
            tmpArgs += self.lecturer
            tmpArgs += "--genre"
            tmpArgs += "Non-Fiction"
            // Make an option in the UI:
            //        tmpArgs += "--overWrite"

            task.arguments = tmpArgs

            task.standardOutput = pipe
            task.standardError = task.standardOutput

            task.launch()
            task.waitUntilExit()

        })
    }


    func parse()
    {
        if self.htmlData == nil
        {
            return
        }

        var courseOutlineParser = TFHpple.hppleWithHTMLData(htmlData)

        var courseTitleXPath =  "//span[@class='courseTitle']/text()"
        var courseOutlineXPath = "//ol[@class='outline']/li"
        var lectureDescriptionXPath = "//div[@class='popup_info_content']/div//text()"
        var lectureTitleXPath = "//div[@class='li_wrapper']/a/text()"
        var lecturerNameXPath = "//div[@class='profName']//text()"

        var lectures = courseOutlineParser.searchWithXPathQuery(courseOutlineXPath)

        var tmpTitle =  courseOutlineParser.searchWithXPathQuery(courseTitleXPath)[0] as TFHppleElement
        seriesTitle = tmpTitle.content.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())

        var tmpLecturer = courseOutlineParser.searchWithXPathQuery(lecturerNameXPath)

        for var i = 0; i < tmpLecturer.count; i++
        {
            var node = tmpLecturer[i] as TFHppleElement
            if node.isTextNode()
            {
                lecturer += node.content
            }
        }
        lecturer = lecturer.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())


        for var i = 0; i < lectures.count; i++
        {
            var desc = ""
            var element = lectures[i] as TFHppleElement

            var descriptionElement = element.searchWithXPathQuery(lectureDescriptionXPath)
            var titleElement = element.searchWithXPathQuery(lectureTitleXPath)

            var titleText = titleElement[0] as TFHppleElement
            var lecture = Lecture()
            lecture.number = i + 1
            lecture.title = fixQuotes(titleText.content)

            for var j = 0; j < descriptionElement.count; j++
            {

                var piece = descriptionElement[j] as TFHppleElement
                if piece.isTextNode()
                {
                    desc += piece.content
                }
            }

            lecture.lectureDescription = fixQuotes(desc.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()))

            self.lectures += lecture
        }

        for lecture in self.lectures
        {
            println("\(lecture.number)\t\(lecture.title)\t\(lecture.lectureDescription)")
        }
    }

    // Change to smart quotes using the linguistic tagger.

    func fixQuotes(text: NSString) -> NSString
    {
        var output: NSString = text
        let tagSchemes = NSLinguisticTagger.availableTagSchemesForLanguage("en")
        let tagger = NSLinguisticTagger(tagSchemes: tagSchemes, options: 0)

        tagger.string = text
        var tokenRanges: NSArray? = nil
        var testRange = NSMakeRange(0, text.length)

        let options = NSLinguisticTaggerOptions(0)

        let tokens = tagger.tagsInRange(testRange, scheme: NSLinguisticTagSchemeLexicalClass, options: options, tokenRanges: &tokenRanges)

        for var i = 0; i < tokens.count; i++
        {
            var range = tokenRanges![i].rangeValue
            var tokenString: NSString = text.substringWithRange(range)

            if tokens[i] as NSString == NSLinguisticTagOpenQuote
            {

                if tokenString == "\""
                {
                    output = output.stringByReplacingCharactersInRange(range, withString: "\u201c")
                    continue
                }
                if tokenString == "'"
                {
                    output = output.stringByReplacingCharactersInRange(range, withString: "\u2018")
                    continue
                }
            }
            if tokens[i] as NSString == NSLinguisticTagCloseQuote
            {
                if tokenString == "\""
                {
                    output = output.stringByReplacingCharactersInRange(range, withString: "\u201d")
                    continue
                }
                if tokenString == "'"
                {
                    output = output.stringByReplacingCharactersInRange(range, withString: "\u2019")
                    continue
                }
            }

        }

// TODO: handle single quote at beginning of word: '20s, etc.

        text.enumerateSubstringsInRange(testRange, options: .ByWords, usingBlock:
            {substring, substringRange, enclosingRange, stop in
                var quoteRange = substring.bridgeToObjectiveC().rangeOfString("'")


                if quoteRange.location != NSNotFound
                {
                    var replacementRange = NSMakeRange(substringRange.location + quoteRange.location, quoteRange.length)
                    output = output.stringByReplacingCharactersInRange(replacementRange, withString: "\u2019")
                }

            })

        return output
    }

    // TODO: Use scripting bridge to import video into iTunes to avoid it playing
    // immediately upon import.

    // Need to get the files created by AtomicParsley or overwrite original files

    func addToiTunes()
    {
        var iTunes = SBApplication(bundleIdentifier: "com.apple.iTunes")
        iTunes.activate()

        // etc
    }

}
