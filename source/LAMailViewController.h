//
//  LAMailViewController.h
//  Letters
//
//  Created by August Mueller on 1/19/10.
//  Copyright 2010 Flying Meat Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface LAMailViewController : NSWindowController <NSOutlineViewDataSource,NSOutlineViewDelegate,NSTableViewDataSource,NSTableViewDelegate> {
    IBOutlet NSTableView *mailboxMessageList;
    IBOutlet NSOutlineView *foldersList;
    IBOutlet NSProgressIndicator *workingIndicator;
    IBOutlet WebView *messageWebView;
    
    LBServer *_server;
    NSMutableArray *_messages;
    NSMutableArray *_folders;
	NSFileWrapper *_folderTree;
    
    NSString *_statusMessage;
}

@property (retain) NSMutableArray *folders;
@property (retain) LBServer *server;
@property (retain) NSString *statusMessage;

+ (id) openNewMailViewController;

- (void) connectToServerAndList;
- (void) getFoldersList;

- (NSFileWrapper*) createFolderTreeFromPaths:(NSArray*) paths;

@end
