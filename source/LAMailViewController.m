//
//  LAMailViewController.m
//  Letters
//
//  Created by August Mueller on 1/19/10.
//  Copyright 2010 Flying Meat Inc. All rights reserved.
//

#import "LAMailViewController.h"
#import "LAAppDelegate.h"
#import "LADocument.h"

#import "NSOperationQueue+LAUtils.h"

@interface LAMailViewController ()
- (NSString *)selectedFolderPath;
@end

@implementation LAMailViewController
@synthesize statusMessage=_statusMessage;

+ (id) openNewMailViewController {
    LAMailViewController *me = [[LAMailViewController alloc] initWithWindowNibName:@"MailView"];
    return [me autorelease];
}

- (id) initWithWindowNibName:(NSString*)nibName {
	self = [super initWithWindowNibName:nibName];
	if (self != nil) {
		//
	}
    
	return self;
}


- (void)dealloc {
    [_statusMessage release];
    
    [super dealloc];
}


- (void)awakeFromNib {
    [mailboxMessageList setDataSource:self];
    [mailboxMessageList setDelegate:self];
    
    [foldersList setDataSource:self];
    [foldersList setDelegate:self];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:LBServerFolderUpdatedNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note)
                                                  {
                                                      debug(@"folder list updated");
                                                      [foldersList reloadData];
                                                  }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:LBServerSubjectsUpdatedNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note)
                                                  {
                                                      debug(@"message list updated.");
                                                      NSString *selectedFolder = [self selectedFolderPath];
                                                      NSString *updatedFolder  = [[note userInfo] objectForKey:@"folderPath"];
                                                      if ([selectedFolder isEqualToString:updatedFolder]) {
                                                          [mailboxMessageList reloadData];
                                                      }
                                                  }];
    
}

- (NSString *)selectedFolderPath {
    
    NSInteger selectedRow = [foldersList selectedRow];
    if (selectedRow < 0) {
        return @"INBOX";
    }
    else {
        LBAccount *currentAccount = [[appDelegate accounts] lastObject];
        return [[[currentAccount server] foldersList] objectAtIndex:selectedRow];        
    }
}

- (NSURL*) cacheFolderURL {
    
    NSString *path = [@"~/Library/Letters/" stringByExpandingTildeInPath];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        
        NSError *err = nil;
        
        [[NSFileManager defaultManager] createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&err];
        if (err) {
            // FIXME: do something sensible with this.
            NSLog(@"Error creating cache folder: %@", err);
        }
    }
    
    return [NSURL fileURLWithPath:path isDirectory:YES];
}

- (void) listFolder:(NSString*)folder {
    
    [_messages removeAllObjects];
    
    _messages = [[_server cachedMessagesForFolder:folder] mutableCopy];
    [mailboxMessageList reloadData];
    
    if (![_server isConnected]) {
        // FIXME: do something nice here.
        NSLog(@"Not connected!");
        return;
    }    
    
    [workingIndicator startAnimation:self];
    
    NSString *format = NSLocalizedString(@"Finding messages in %@", @"Finding messages in %@");
    [self setStatusMessage:[NSString stringWithFormat:format, folder]];
    
    [[NSOperationQueue globalOperationQueue] addOperationWithBlock:^{
      if(![self.folders count]) {
        [self getFoldersList];
      }
        
        LBFolder *inbox   = [_server folderWithPath:folder];
        NSSet *messageSet = [inbox messageObjectsFromIndex:1 toIndex:0]; 
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [_messages removeAllObjects];
            [_messages addObjectsFromArray:[messageSet allObjects]];
            
            [mailboxMessageList reloadData];
            
            [self setStatusMessage:NSLocalizedString(@"Download message bodies", @"Download message bodies")];
        }];
        
        
        for (LBMessage *msg in messageSet) {
            [msg body]; // pull down the body. in the background.
        }
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self setStatusMessage:nil];
            [workingIndicator stopAnimation:self];
        }];
    }];
}

//moved into a separate method; probably still not being called from a great place
- (void) getFoldersList {
	NSMutableArray *folders = [NSMutableArray array];
	
	NSError *err = nil;
	
	self.folders = [[[_server subscribedFolders:&err] mutableCopy] autorelease];
	
	self->_folderTree = [self createFolderTreeFromPaths:self.folders];
	
	if (err) {
		// do something nice with this.
		NSLog(@"err: %@", err);
		return;
	}
	
  [[NSOperationQueue globalOperationQueue] addOperationWithBlock:^{
		[foldersList reloadData];
  }];
}

- (void) connectToServerAndList {
    
    LBAccount *account = [[appDelegate accounts] lastObject];
    
    if (![[account password] length]) {
        [appDelegate openPreferences:nil];
        return;
    }
    
    [self setStatusMessage:NSLocalizedString(@"Connecting to server", @"Connecting to server")];
    
    // FIXME: this ivar shouldn't be here.  It probably belongs in the account?
    _server = [[LBServer alloc] initWithAccount:account usingCacheFolder:[self cacheFolderURL]];
    
    [_server loadCache]; // do this right away, so we can see our account info.  It's also kind of slow.
    
    // load our folder cache first.
    self.folders = [[[_server cachedFolders] mutableCopy] autorelease];
    [foldersList reloadData];
    
    NSError *err = nil;
    
    if ([_server connect:&err]) {
        [self listFolder:@"INBOX"];
    }
    else {
        NSLog(@"Could not connect");
    }
    
    [[NSOperationQueue globalOperationQueue] addOperationWithBlock:^{
      [foldersList reloadData];
    }];

    if (err) {
        
        // OH CRAP.
        
        NSString *desc = [err localizedDescription];
        
        desc = desc ? desc : NSLocalizedString(@"Unknown Error", @"Unknown Error");
        
        NSRunAlertPanel(@"Error Connecting", desc, @"OK", nil, nil);
        
    }
    
    
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    
    if ([notification object] == mailboxMessageList) {
        NSInteger selectedRow = [mailboxMessageList selectedRow];
        if (selectedRow < 0) {
            [[messageWebView mainFrame] loadHTMLString:@"This area intentionally left blank." baseURL:nil];
        }
        else {
            
            LBAccount *currentAccount = [[appDelegate accounts] lastObject];
            NSArray *messageList = [[currentAccount server] messageListForPath:[self selectedFolderPath]];
            
            LBMessage *msg = [messageList objectAtIndex:selectedRow];
            
            NSString *message = nil;
            
            if ([msg messageDownloaded]) {

                message = NSLocalizedString(@"Loading message…", @"Loading message…");
                [msg retain];
                [[NSOperationQueue globalOperationQueue] addOperationWithBlock:^{
                    NSString *htmlMessage = [msg htmlBody];
                    htmlMessage = [LAPrefs boolForKey:@"chocklock"] ? [htmlMessage uppercaseString] : htmlMessage;
					if ([htmlMessage length] == 0) {
						htmlMessage = [NSString stringWithFormat:@"<pre>%@</pre>", [msg body]];
					}
                    [htmlMessage retain];
                    [msg release];
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        [[messageWebView mainFrame] loadHTMLString:htmlMessage baseURL:nil];
                        [htmlMessage release];
                    }];
                }];
            }
            else {
                message = NSLocalizedString(@"This message has not been downloaded from the server yet.", @"This message has not been downloaded from the server yet.");
            }
            
            message = [LAPrefs boolForKey:@"chocklock"] ? [message uppercaseString] : message;
            [[messageWebView mainFrame] loadHTMLString:message baseURL:nil];
        }
        }
    }
    
    else if ([notification object] == foldersList) {
        [mailboxMessageList reloadData];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
	return [_messages count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    LBMessage *msg = [_messages objectAtIndex:rowIndex];
    
    // just grab the last account.
    LBAccount *currentAccount = [[appDelegate accounts] lastObject];
    
    if (aTableView == foldersList) {
        return [[[currentAccount server] foldersList] count];
    }
    
    NSArray *messageList = [[currentAccount server] messageListForPath:[self selectedFolderPath]];
    
    return [messageList count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	
    // just grab the last account.
    LBAccount *currentAccount = [[appDelegate accounts] lastObject];
    
    if (aTableView == foldersList) {
        
        NSString *folderName = [[[currentAccount server] foldersList] objectAtIndex:rowIndex];
        
        /*
        if ([folderName hasPrefix:@"INBOX."]) {
            folderName = [folderName substringFromIndex:6];
        }
        */
        
        // this will be taken out eventually.  But I just can't help myself.
        
        return [LAPrefs boolForKey:@"chocklock"] ? [folderName uppercaseString] : folderName;
    }
    
    NSArray *messageList = [[currentAccount server] messageListForPath:[self selectedFolderPath]];
    
    LBMessage *msg = [messageList objectAtIndex:rowIndex];
    
    NSString *identifier = [aTableColumn identifier];
    
    return [LAPrefs boolForKey:@"chocklock"] ? [[msg valueForKeyPath:identifier] uppercaseString] : [msg valueForKeyPath:identifier];
    
}

//Outline view datasource

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
	if (item == nil) {
		return [[self->_folderTree fileWrappers] objectForKey:[[[self->_folderTree fileWrappers] allKeys] objectAtIndex:index]];
	}
	return [[item fileWrappers] objectForKey:[[[item fileWrappers] allKeys] objectAtIndex:index]];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
	if([[item fileWrappers] count] > 0) {
		return YES;
	}
	return NO;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {	
	if(item == nil) {
		return [[self->_folderTree fileWrappers] count];
	}
	else {
		return [[item fileWrappers] count];
	}
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
	return [item preferredFilename];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item {
	return NO;
}

//workaround; selecting a parent directory crashes
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
	if([[item fileWrappers] count] > 0) {
		return NO;
	}
	return YES;
}


//kind of a misuse of filewrappers but they get the job done
- (NSFileWrapper*) createFolderTreeFromPaths:(NSArray*) paths {
	NSFileWrapper* treeBase = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:nil];
	for(NSString* path in paths) {
		NSArray* components = [path pathComponents];
		NSFileWrapper* here = treeBase;
		for(NSString* component in components) {
			if(![[here fileWrappers] objectForKey:component]) {
				NSFileWrapper* newDir = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:nil];
				[newDir setPreferredFilename:component];
				[newDir setFilename:path];
				[here addFileWrapper:newDir];
			}
			here = [[here fileWrappers] objectForKey:component];
		}
	}
	return treeBase;
}

- (void) outlineViewSelectionDidChange:(NSNotification *)notification {
    if ([notification object] == foldersList) {
        NSUInteger selectedRow = [foldersList selectedRow];
		[self listFolder:[[foldersList itemAtRow:selectedRow] filename]];
    }	
}

// FIXME: put this somewhere where it makes more sense, maybe a utils file?

NSString *FQuote(NSString *s) {
    NSMutableString *ret = [NSMutableString string];
    s = [s stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    for (NSString *line in [s componentsSeparatedByString:@"\n"]) {
        [ret appendFormat:@">%@\n", line];
    }
    return ret;
}

NSString *FRewrapLines(NSString *s, int len) {
    
    NSMutableString *ret = [NSMutableString string];
    
    
    s = [s stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    
    for (NSString *line in [s componentsSeparatedByString:@"\n"]) {
        
        if (![line length]) {
            [ret appendString:@"\n"];
            continue;
        }
        
        int idx = 0;
        
        while ((idx < [line length]) && ([line characterAtIndex:idx] == '>')) {
            idx++;
        }
        
        NSMutableString *pre = [NSMutableString string];
        
        for (int i = 0; i < idx; i++) {
            [pre appendString:@">"];
        }
        
        NSString *oldLine = [line substringFromIndex:idx];
        
        NSMutableString *newLine = [NSMutableString string];
        
        [newLine appendString:pre];
        
        for (NSString *word in [oldLine componentsSeparatedByString:@" "]) {
            
            if ([newLine length] + [word length] > len) {
                [ret appendString:newLine];
                [ret appendString:@"\n"];
                [newLine setString:pre];
            }
            
            if ([word length] && [newLine length]) {
                [newLine appendString:@" "];
            }
            
            [newLine appendString:word];
            
        }
        
        [ret appendString:newLine];
        [ret appendString:@"\n"];
        
    }
    
    return ret;
}




- (void) replyToSelectedMessage:(id)sender {
    
    
    NSInteger selectedRow = [mailboxMessageList selectedRow];
    
    if (selectedRow < 0) {
        // FIXME: we should validate the menu item.
        return;
    }
    
    LBAccount *currentAccount = [[appDelegate accounts] lastObject];
    
    NSArray *messageList = [[currentAccount server] messageListForPath:[self selectedFolderPath]];
    
    LBMessage *msg = [messageList objectAtIndex:selectedRow];
    
    if (![msg messageDownloaded]) {
        // FIXME: validate for this case as well.
        return;
    }
    
    NSDocumentController *dc = [NSDocumentController sharedDocumentController];
    NSError *err = nil;
    LADocument *doc = [dc openUntitledDocumentAndDisplay:YES error:&err];
    
    LBAccount *account = [[appDelegate accounts] lastObject];
    
    [doc setFromList:[account fromAddress]];
    [doc setToList:[[msg sender] email]];
    
    // fixme - 72?  a pref maybe?
    [doc setMessage:FRewrapLines(FQuote([msg body]), 72)];
    
    NSString *subject = [msg subject];
    if (![[subject lowercaseString] hasPrefix:@"re: "]) {
        subject = [NSString stringWithFormat:@"Re: ", subject];
    }
    
    [doc setSubject:subject];
    
    [doc updateChangeCount:NSChangeDone];
    
}


@end


