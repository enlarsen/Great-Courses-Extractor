//
//  GreatCoursesViewController.m
//  Great-Courses-Extractor
//
//  Created by Erik Larsen on 10/8/14.
//  Copyright (c) 2014 Erik Larsen. All rights reserved.
//

#import "GreatCoursesViewController.h"
#import "Lecture.h"
#import "TFHpple.h"

@interface GreatCoursesViewController ()

@property (strong, nonatomic) NSData *htmlData;
@property (strong, nonatomic) NSURL *url;
@property (strong, nonatomic) NSString *seriesTitle;
@property (strong, nonatomic) NSString *lecturer;
@property (strong, nonatomic) dispatch_queue_t serialQueue;
@property (weak) IBOutlet NSArrayController *lectureArrayController;


@property (weak) IBOutlet NSTextField *urlTextField;
@property (weak) IBOutlet NSWindow *window;

@end

@implementation GreatCoursesViewController

#pragma mark - properties

- (dispatch_queue_t)serialQueue
{
    if(!_serialQueue)
    {
        _serialQueue = dispatch_queue_create("com.elarsen.GCEQ", DISPATCH_QUEUE_SERIAL);
    }
    return _serialQueue;
}

- (NSArray *)lectures
{
    if(!_lectures)
    {
        _lectures = [[NSMutableArray alloc] init];
    }
    return _lectures;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do view setup here.
}

- (IBAction)scrape:(NSButton *)sender
{
    [self.lectures removeAllObjects];
    self.url = [[NSURL alloc] initWithString:self.urlTextField.stringValue];
    dispatch_async(self.serialQueue,
    ^{
        self.htmlData = [[NSData alloc] initWithContentsOfURL:self.url];

        dispatch_async(dispatch_get_main_queue(),
        ^{
            [self parse];
            self.window.title = self.seriesTitle;
        });

    });

}

- (IBAction)addToFiles:(NSButton *)sender
{
    NSOpenPanel *openPanel = [[NSOpenPanel alloc] init];
    openPanel.allowedFileTypes = @[@"m4v", @"mp4", @"M4V", @"MP4"];
    openPanel.canSelectHiddenExtension = YES;
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = NO;
    openPanel.allowsMultipleSelection = YES;

    [openPanel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result)
    {
        if(result == NSFileHandlingPanelOKButton)
        {
            for(int i = 0; i < openPanel.URLs.count; i++)
            {
                [self metadataTask:openPanel.URLs[i] index:i];
            }
        }
    }];
}

- (void)metadataTask:(NSURL *)fileURL index:(int)index
{
    dispatch_async(self.serialQueue,
    ^{
        NSTask *task = [[NSTask alloc] init];
        NSPipe *pipe = [[NSPipe alloc] init];
//        NSFileHandle *file = [pipe fileHandleForReading];
        Lecture *lecture = self.lectures[index];
        NSString *trackNumber = [NSString stringWithFormat:@"%d/%lu", index + 1, (unsigned long)self.lectures.count];
        NSString *episodeNumber = [NSString stringWithFormat:@"%d", index + 1];

        task.launchPath = [[NSBundle mainBundle] pathForResource:@"AtomicParsley"
                                                          ofType:nil];
        task.arguments = @[fileURL.path,
                           @"--stik", @"value=10",
                           @"--title", lecture.title,
                           @"--TVShowName", self.seriesTitle,
                           @"--TVSeasonNum", @"1",
                           @"--description", lecture.lectureDescription,
                           @"--longdesc", lecture.lectureDescription,
                           @"--tracknum", trackNumber,
                           @"--TVEpisodeNum", episodeNumber,
                           @"--artist", self.lecturer,
                           @"--genre", @"Non-Fiction"
                           ];
        task.standardOutput = pipe;
        task.standardError = task.standardOutput;

        [task launch];
        [task waitUntilExit];
    });
}

- (void)parse
{
    if(!self.htmlData)
    {
        return;
    }

    TFHpple *courseOutlineParser = [TFHpple hppleWithHTMLData:self.htmlData];

    NSString *courseTitleXPath =  @"//h1[@class='product-name']/text()";
    NSString *courseOutlineXPath = @"//ul[@class='lectures-list']/li";
    NSString *lectureDescriptionXPath = @"//div[@class='lecture-description-block right' or @class='lecture-description-block left']/text()";
    NSString *lectureTitleXPath = @"//div[@class='lecture-title']/text()";
    NSString *lecturerNameXPath = @"//div[@class='professor-data']/a[@class='name']/text()";

    NSArray *lectures = [courseOutlineParser searchWithXPathQuery:courseOutlineXPath];
    TFHppleElement *tmpTitle = [courseOutlineParser searchWithXPathQuery:courseTitleXPath][0];
    self.seriesTitle = [tmpTitle.content
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *tmpLecturer = [courseOutlineParser searchWithXPathQuery:lecturerNameXPath];

    NSMutableString *lecturer = [[NSMutableString alloc] init];
    for(TFHppleElement *node in tmpLecturer)
    {
        if(node.isTextNode)
        {
            [lecturer appendString:node.content];
        }
    }
    self.lecturer = [lecturer stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    for(int i = 0; i < lectures.count; i++)
    {
        TFHppleElement *element = lectures[i];
        NSArray *descriptionElements = [element searchWithXPathQuery:lectureDescriptionXPath];
        NSArray *titleElements = [element searchWithXPathQuery:lectureTitleXPath];

        TFHppleElement *titleText = titleElements[0];
        Lecture *lecture = [[Lecture alloc] init];
        lecture.number = i + 1;
        lecture.title = [self fixQuotes:[titleText.content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];

        NSMutableString *desc = [[NSMutableString alloc] init];
        for(TFHppleElement *piece in descriptionElements)
        {

            if(piece.isTextNode)
            {
                [desc appendString:piece.content];
            }
        }
        lecture.lectureDescription = [self fixQuotes:[desc stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];

        [self willChangeValueForKey:@"lectures"];
        [self.lectures addObject:lecture];
        [self didChangeValueForKey:@"lectures"];

    }

    for(Lecture *lecture in self.lectures)
    {
        NSLog(@"%d\t%@\t%@", lecture.number, lecture.title, lecture.lectureDescription);
    }

}

- (NSString *)fixQuotes:(NSString *)text
{
    NSMutableString *output = [text mutableCopy];

    NSArray *tagSchemes = [NSLinguisticTagger availableTagSchemesForLanguage:@"en"];
    NSLinguisticTagger *tagger = [[NSLinguisticTagger alloc] initWithTagSchemes:tagSchemes options:0];

    tagger.string = text;
    NSArray *tokenRanges;
    NSRange testRange = NSMakeRange(0, text.length);

    NSArray *tokens = [tagger tagsInRange:testRange
                                scheme:NSLinguisticTagSchemeLexicalClass
                                options:0
                                tokenRanges:&tokenRanges];

    for(int i = 0; i < tokens.count; i++)
    {
        NSRange range = [tokenRanges[i] rangeValue];
        NSString *tokenString = [text substringWithRange:range];

        if([tokens[i] isEqualToString:NSLinguisticTagOpenQuote])
        {
            if([tokenString isEqualToString:@"\""])
            {
                [output replaceCharactersInRange:range withString:@"\u201c"];
                continue;
            }
            if([tokenString isEqualToString:@"'"])
            {
                [output replaceCharactersInRange:range withString:@"\u2018"];
                continue;
            }
        }
        if([tokens[i] isEqualToString:NSLinguisticTagCloseQuote])
        {
            if([tokenString isEqualToString:@"\""])
            {
                [output replaceCharactersInRange:range withString:@"\u201d"];
                continue;
            }
            if([tokenString isEqualToString:@"'"])
            {
                [output replaceCharactersInRange:range withString:@"\u2019"];
                continue; // not really necessary
            }
        }

    }

    [text enumerateSubstringsInRange:testRange
                             options:NSStringEnumerationByWords
                          usingBlock:^(NSString *substring,
                                       NSRange substringRange,
                                       NSRange enclosingRange,
                                       BOOL *stop)
    {
        NSRange quoteRange = [substring rangeOfString:@"'"];
        if(quoteRange.location != NSNotFound)
        {
            NSRange replacementRange = NSMakeRange(substringRange.location + quoteRange.location,
                                                   quoteRange.length);
            [output replaceCharactersInRange:replacementRange withString:@"\u2019"];
        }
    }];

    return output;
}

@end
