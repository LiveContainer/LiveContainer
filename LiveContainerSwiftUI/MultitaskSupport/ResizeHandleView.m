//
//  ResizeHandleView.m
//  LiveContainer
//
//  Created by Duy Tran on 2/6/25.
//
#import "ResizeHandleView.h"

@implementation ResizeHandleView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.layer.masksToBounds = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    UIView *backgroundView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width*sqrt(2), frame.size.height*sqrt(2))];
    backgroundView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.2];
    backgroundView.center = CGPointMake(frame.size.width, frame.size.height);
    backgroundView.transform = CGAffineTransformMakeRotation(M_PI_4);
    [self addSubview:backgroundView];
    return self;
}
@end
