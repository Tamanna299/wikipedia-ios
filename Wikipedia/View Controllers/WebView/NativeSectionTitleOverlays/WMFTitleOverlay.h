//  Created by Monte Hurd on 8/4/15.
//  Copyright (c) 2015 Wikimedia Foundation. Provided under MIT-style license; please copy and modify!

#import <UIKit/UIKit.h>
#import "WMFEditSectionProtocol.h"

@interface WMFTitleOverlay : UIView

@property (nonatomic) NSNumber* sectionId;
@property (nonatomic, strong) NSString* title;

@property (nonatomic, weak) id <WMFEditSectionDelegate> editSectionDelegate;

@end
