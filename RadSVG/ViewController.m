//
//  ViewController.m
//  RadSVG
//
//  Created by Tim Burks on 5/7/15.
//  Copyright (c) 2015 Radtastical. All rights reserved.
//

#import "ViewController.h"
#import "RadSVG.h"

@interface ViewController ()
@property (nonatomic, strong) RadSVGView *svgView;
@property (nonatomic, strong) NSMutableArray *svgFileNames;
@property (nonatomic, strong) UILabel *svgLabel;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.svgFileNames = [NSMutableArray array];
    NSArray *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[NSBundle mainBundle] resourcePath] error:NULL];
    for (NSString *fileName in fileNames) {
        if ([[fileName pathExtension] isEqualToString:@"svg"]) {
            [self.svgFileNames addObject:[fileName stringByDeletingPathExtension]];
        }
    }
    
    self.svgView = [[RadSVGView alloc] initWithFrame:CGRectInset(self.view.bounds, 20, 20)];
    self.svgView.autoresizingMask = UIViewAutoresizingFlexibleWidth+UIViewAutoresizingFlexibleHeight;
    self.svgView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.svgView];
    
    CGRect topCenter = self.view.bounds;
    topCenter.origin.y = topCenter.size.height - 40;
    topCenter.size.height = 40;
    self.svgLabel = [[UILabel alloc] initWithFrame:topCenter];
    self.svgLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.svgLabel];
    
    UITapGestureRecognizer *tapGestureRecognizer =
    [[UITapGestureRecognizer alloc]
     initWithTarget:self action:@selector(tapped:)];
    [self.view addGestureRecognizer:tapGestureRecognizer];

    [self setImage];
}

- (void) tapped:(UIGestureRecognizer *) recognizer
{
    [self setImage];
}

- (void) setImage
{
    static int i = 0;
    NSString *name = self.svgFileNames[i++];
    if (i == [self.svgFileNames count]) {
        i = 0;
    }
    
    NSLog(@"Loading %@", name);
    NSData *svgData = [NSData dataWithContentsOfFile:
                       [[NSBundle mainBundle]
                        pathForResource:name
                        ofType:@"svg"]];
    self.svgView.svgObject = [RadSVGObject SVGObjectWithData:svgData];
    self.svgLabel.text = name;
}
@end
