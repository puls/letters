//
//  LADocument.m
//  Letters
//
//  Created by August Mueller on 1/19/10.
//

#import "LADocument.h"
#import "LAAppDelegate.h"

#import "NSOperationQueue+LAUtils.h"

@implementation LADocument
@synthesize statusMessage=_statusMessage;
@synthesize toList=_toList;
@synthesize fromList=_fromList;
@synthesize subject=_subject;
@synthesize message=_message;

- (id)init
{
    self = [super init];
    if (self) {
    
        // Add your subclass-specific initialization here.
        // If an error occurs here, send a [self release] message and return nil.
    
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_statusMessage release];
    [super dealloc];
}


- (NSString *)windowNibName
{
    // Override returning the nib file name of the document
    // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this method and override -makeWindowControllers instead.
    return @"LADocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
    [super windowControllerDidLoadNib:aController];
    // Add any code here that needs to be executed once the windowController has loaded the document's window.
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    // Insert code here to write your document to data of the specified type. If the given outError != NULL, ensure that you set *outError when returning nil.

    // You can also choose to override -fileWrapperOfType:error:, -writeToURL:ofType:error:, or -writeToURL:ofType:forSaveOperation:originalContentsURL:error: instead.

    // For applications targeted for Panther or earlier systems, you should use the deprecated API -dataRepresentationOfType:. In this case you can also choose to override -fileWrapperRepresentationOfType: or -writeToFile:ofType: instead.

    if ( outError != NULL ) {
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:NULL];
	}
	return nil;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
    // Insert code here to read your document from the given data of the specified type.  If the given outError != NULL, ensure that you set *outError when returning NO.

    // You can also choose to override -readFromFileWrapper:ofType:error: or -readFromURL:ofType:error: instead. 
    
    // For applications targeted for Panther or earlier systems, you should use the deprecated API -loadDataRepresentation:ofType. In this case you can also choose to override -readFromFile:ofType: or -loadFileWrapperRepresentation:ofType: instead.
    
    if ( outError != NULL ) {
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:NULL];
	}
    return YES;
}

- (void) sendMessage:(id)sender {
    
    // make the message binding do it's thing.
    // FIXME: is there a better way?  I'm sure there is...
    [[progressIndicator window] makeFirstResponder:nil];
    
    LBAccount *account = [[appDelegate accounts] lastObject];
    
    assert(account);
    
    debug(@"_message: %@", _message);
    
    if (![_fromList length]) {
        debug(@"need a from!");
        return;
    }
    
    if (![_toList length]) {
        debug(@"need a _toList!");
        return;
    }
    
    NSMutableSet *toSet = [NSMutableSet set];
    
    for (NSString *addr in [_toList componentsSeparatedByString:@" "]) {
        [toSet addObject:[LBAddress addressWithName:@"" email:addr]];
    }
    
    
    LBMessage *msg = [[LBMessage alloc] init];
	[msg setTo:toSet];
	[msg setFrom:[NSSet setWithObject:[LBAddress addressWithName:@"" email:_fromList]]];
	[msg setBody:[[_message copy] autorelease]];
	[msg setSubject:_subject];
    
    [self setStatusMessage:NSLocalizedString(@"Sending message", @"Sending message")];
    [progressIndicator startAnimation:self];
    
    [[NSOperationQueue globalOperationQueue] addOperationWithBlock:^{
        
        // FIXME: how do we know if it was successful or not?
        
        [LBSMTPConnection sendMessage:msg
                               server:[account smtpServer]
                             username:[account username]
                             password:[account password]
                                 port:25 // fixme
                               useTLS:YES // fixme, lookup in acct
                              useAuth:YES];
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self setStatusMessage:nil];
            [progressIndicator stopAnimation:self];
            [self close];
        }];
        
        [msg release];
    }];
}

@end
