//
//  Lecture.h
//  Great-Courses-Extractor
//
//  Created by Erik Larsen on 10/8/14.
//  Copyright (c) 2014 Erik Larsen. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Lecture : NSObject

@property (nonatomic) int number;
@property (strong, nonatomic) NSString *title;
@property (strong, nonatomic) NSString *lectureDescription;

@end
