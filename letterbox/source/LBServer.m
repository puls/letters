//
//  LBServer.m
//  LetterBox
//
//  Created by August Mueller on 1/20/10.
//  Copyright 2010 Flying Meat Inc. All rights reserved.
//

#import "LBServer.h"
#import "LBAccount.h"
#import "LetterBoxTypes.h"
#import "LBFolder.h"
#import "LBAddress.h"
#import "LBMessage.h"
#import "FMDatabase.h"
#import "LBIMAPConnection.h"


NSString *LBServerFolderUpdatedNotification = @"LBServerFolderUpdatedNotification";
NSString *LBServerSubjectsUpdatedNotification = @"LBServerSubjectsUpdatedNotification";
NSString *LBServerBodiesUpdatedNotification = @"LBServerBodiesUpdatedNotification";

// these are defined in LBActivity.h, but they need to go somewhere and I'm not making a .m just for them.
NSString *LBActivityStartedNotification = @"LBActivityStartedNotification";
NSString *LBActivityUpdatedNotification = @"LBActivityUpdatedNotification";
NSString *LBActivityEndedNotification   = @"LBActivityEndedNotification";

@implementation LBServer
@synthesize account=_account;
@synthesize baseCacheURL=_baseCacheURL;
@synthesize accountCacheURL=_accountCacheURL;
@synthesize foldersCache=_foldersCache;
@synthesize foldersList=_foldersList;

- (id) initWithAccount:(LBAccount*)anAccount usingCacheFolder:(NSURL*)cacheFileURL {
    
	self = [super init];
	if (self != nil) {
		self.account        = anAccount;
        self.baseCacheURL   = cacheFileURL;
        
        _inactiveIMAPConnections = [[NSMutableArray array] retain];
        _activeIMAPConnections = [[NSMutableArray array] retain];
        _foldersCache = [[NSMutableDictionary dictionary] retain];
        _foldersList  = [[NSArray array] retain];
	}
    
	return self;
}


- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_account release];
    [_baseCacheURL release];
    [_accountCacheURL release];
    [_cacheDB release];
    
    [_inactiveIMAPConnections release];
    [_activeIMAPConnections release];
    
    [super dealloc];
}

- (LBIMAPConnection*) checkoutIMAPConnection {
    
    // FIXME: this method isn't thread safe
    if (![[NSThread currentThread] isMainThread]) {
        NSLog(@"UH OH THIS IS BAD CHECKING OUT ON A NON MAIN THREAD NOOO.");
    }
    
    
    // FIXME: need to set an upper limit on these guys.
    
    LBIMAPConnection *conn = [_inactiveIMAPConnections lastObject];
    
    if (!conn) {
        // FIXME: what about a second connection that hasn't been connected yet?
        // should we worry about that?
        conn = [[[LBIMAPConnection alloc] init] autorelease];
    }
    
    [_activeIMAPConnections addObject:conn];
    
    return conn;
}

- (void) checkInIMAPConnection:(LBIMAPConnection*) conn {
    
    // FIXME: aint' thread safe.
    if (![[NSThread currentThread] isMainThread]) {
        NSLog(@"UH OH THIS IS BAD CHECKING IN ON A NON MAIN THREAD NOOO.");
    }
    
    // Possible solution- only ever checkout / check in on main thread?
    
    [_inactiveIMAPConnections addObject:conn];
    [_activeIMAPConnections removeObject:conn];
    [conn setActivityStatusAndNotifiy:nil];
}

- (void) connectUsingBlock:(void (^)(BOOL, NSError *))block {
    LBIMAPConnection *conn = [self checkoutIMAPConnection];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^(void){
        
        [conn setActivityStatusAndNotifiy:NSLocalizedString(@"Connecting", @"Connecting")];
        
        NSError *err = nil;
        BOOL success = [conn connectWithAccount:[self account] error:&err];
        
        if (block) {
            dispatch_async(dispatch_get_main_queue(),^ {
                
                block(success, err);
                
                [self checkInIMAPConnection:conn];
            });
        }
    });
}

- (void) checkForMail {
    // weeeeeee
    
    LBIMAPConnection *conn = [self checkoutIMAPConnection];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^(void){
        
        if (![conn isConnected]) {
            [conn setActivityStatusAndNotifiy:NSLocalizedString(@"Connecting", @"Connecting")];
            NSError *err = nil;
            if (![conn connectWithAccount:[self account] error:&err]) {
                NSLog(@"err: %@", err);
                // FIXME: remove / invalidate the connection so it isn't used again?
                return;
            }
        }
        
        [conn setActivityStatusAndNotifiy:NSLocalizedString(@"Updating folder list", @"Updating folder list")];
        NSError *err    = nil;
        NSArray *list   = [conn subscribedFolderNames:&err];
        
        if (err) {
            // do something nice with this.
            NSLog(@"err: %@", err);
            return;
        }
        
        self.foldersList = list;
        
        dispatch_async(dispatch_get_main_queue(),^ {
            [[NSNotificationCenter defaultCenter] postNotificationName:LBServerFolderUpdatedNotification
                                                                object:self
                                                              userInfo:nil];
        });
        
        
        
        for (NSString *folderPath in list) {
            
            NSString *status = NSLocalizedString(@"Finding messages in '%@'", @"Finding messages in '%@'");
            [conn setActivityStatusAndNotifiy:[NSString stringWithFormat:status, folderPath]];
            
            LBFolder *folder    = [[LBFolder alloc] initWithPath:folderPath inIMAPConnection:conn];
            
            NSSet *messageSet   = [folder messageObjectsFromIndex:1 toIndex:0]; 
            
            if (!messageSet || ![folder connected]) {
                NSLog(@"Could not get folder listing for %@", list);
                [folder release];
                continue;
            }
            
            
            NSArray *messages = [[messageSet allObjects] sortedArrayUsingComparator:^(LBMessage *obj1, LBMessage *obj2) {
                // FIXME: sort by date or something, not subject.
                return [[obj1 subject] localizedCompare:[obj2 subject]];
            }];
            
            dispatch_async(dispatch_get_main_queue(),^ {
                
                [_foldersCache setObject:messages forKey:folderPath];
                
                [[NSNotificationCenter defaultCenter] postNotificationName:LBServerSubjectsUpdatedNotification
                                                                    object:self
                                                                  userInfo:[NSDictionary dictionaryWithObject:folderPath
                                                                                                       forKey:@"folderPath"]];
            });
            
            NSInteger idx = 0;
            
            for (LBMessage *msg in messages) {
                idx++;
                
                NSString *status = NSLocalizedString(@"Loading message %d of %d messages in '%@'", @"Loading message %d of %d messages in '%@'");
                [conn setActivityStatusAndNotifiy:[NSString stringWithFormat:status, idx, [messages count], folderPath]];
                
                [msg body]; // pull down the body.
            }
            
            dispatch_async(dispatch_get_main_queue(),^ {
                [[NSNotificationCenter defaultCenter] postNotificationName:LBServerBodiesUpdatedNotification
                                                                    object:self
                                                                  userInfo:[NSDictionary dictionaryWithObject:folderPath forKey:@"folderPath"]];
            });
            
            [folder release];
            
            debug(@"Done folder %@", folderPath);
        }
        
        dispatch_async(dispatch_get_main_queue(),^ {
            [self checkInIMAPConnection:conn];
        });
        
        
    });
    
}

- (NSArray*) messageListForPath:(NSString*)folderPath {
    return [_foldersCache objectForKey:folderPath];
}


- (void) makeCacheFolders {
    
    NSError *err = nil;
    BOOL madeDir = [[NSFileManager defaultManager] createDirectoryAtPath:[_accountCacheURL path]
                                             withIntermediateDirectories:YES
                                                              attributes:nil
                                                                   error:&err];
    if (err || !madeDir) {
        // FIXME: do something sensible with this.
        NSLog(@"Error creating cache folder: %@", err);
    }
}

- (void) loadCache {
    
    assert(_baseCacheURL);
    assert(_account);
    
    
    NSString *cacheFolder = [NSString stringWithFormat:@"imap-%@@%@.letterbox", [_account username], [_account imapServer]];
    
    self.accountCacheURL  = [_baseCacheURL URLByAppendingPathComponent:cacheFolder];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:[_accountCacheURL path]]) {
        [self makeCacheFolders];
    }
    
    NSString *databasePath = [[_accountCacheURL URLByAppendingPathComponent:@"letterscache.db"] path];
    
    debug(@"databasePath: %@", databasePath);
    
    _cacheDB = [[FMDatabase databaseWithPath:databasePath] retain];
    
    if (![_cacheDB open]) {
        NSLog(@"Can't open the %@!", cacheFolder);
        // FIXME: do something nice here for the user.
        [_cacheDB release];
        _cacheDB = nil;
        return;
    }
    
    // now we setup some tables.
    
    FMResultSet *rs = [_cacheDB executeQuery:@"select name from SQLITE_MASTER where name = 'letters_meta'"];
    
    
    if (![rs next]) {
        debug(@"setting up new tables.");
        [rs close];
        // if we don't get a result, then we'll need to make our tables.
        
        int schemaVersion = 1;
        
        [_cacheDB beginTransaction];
        
        // simple key value stuff, for config info.  The type is the value type.  Eventually i'll add something like:
        // - (void) setDBProperty:(id)obj forKey:(NSString*)key
        // - (id) dbPropertyForKey:(NSString*)key
        // which just figures out what the type is, and stores it appropriately.
        
        [_cacheDB executeUpdate:@"create table letters_meta ( name text, type text, value blob )"];
        
        [_cacheDB executeUpdate:@"insert into letters_meta (name, type, value) values (?,?,?)", @"schemaVersion", @"int", [NSNumber numberWithInt:schemaVersion]];
        
        // this table obviously isn't going to cut it.  It needs multiple to's and other nice things.
        [_cacheDB executeUpdate:@"create table message ( messageid text primary key,\n\
                                                   folder text,\n\
                                                   subject text,\n\
                                                   fromAddress text, \n\
                                                   toAddress text, \n\
                                                   receivedDate float,\n\
                                                   sendDate float\n\
                                                 )"];
        
        // um... do we need anything else?
        [_cacheDB executeUpdate:@"create table folder ( folder text, subscribed int )"];
        
        [_cacheDB commit];
    }
}

- (void) saveMessagesToCache:(NSSet*)messages forFolder:(NSString*)folderName {

#ifdef LBUSECACHE
    [_cacheDB beginTransaction];
    
    // FIXME - the dates are allllllll off.
    
    // this feels icky.
    [_cacheDB executeUpdate:@"delete from message where folder = ?", folderName];
    
    for (LBMessage *msg in messages) {
        [_cacheDB executeUpdate:@"insert into message ( messageid, folder, subject, fromAddress, toAddress, receivedDate, sendDate) values (?, ?, ?, ?, ?, ?, ?)",
                                [msg messageId], folderName, [msg subject], [[[msg from] anyObject] email], [[[msg to] anyObject] email], [NSDate distantFuture], [NSDate distantPast]];
    }
    
    [_cacheDB commit];
    
    // we do this outside the transaction so that we don't hold up the db.
    
    NSURL *folderURL = [_accountCacheURL URLByAppendingPathComponent:folderName];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:[folderURL path]]) {
        NSError *err = nil;
        BOOL madeDir = [[NSFileManager defaultManager] createDirectoryAtPath:[folderURL path]
                                                 withIntermediateDirectories:YES
                                                                  attributes:nil
                                                                       error:&err];
        if (err || !madeDir) {
            // FIXME: do something sensible with this.
            NSLog(@"Error creating cache folder: %@ %@", [folderURL path], err);
        }
    }
    
    for (LBMessage *msg in messages) {
        
        // FIXME: some way to fail gracefully?
        
        NSString *messageFile = [NSString stringWithFormat:@"%@.letterboxmsg", [msg messageId]];
        
        NSURL *messageCacheURL = [folderURL URLByAppendingPathComponent:messageFile];
        
        [msg writePropertyListRepresentationToURL:messageCacheURL];
    }
#endif
}

// FIXME: need to setup a way to differentiate between subscribed and non subscribed.
- (void) saveFoldersToCache:(NSArray*)messages {
    
    // I'm just going to turn this off for now.  It's stupidly incomplete
    
#ifdef LBUSECACHE
    
    [_cacheDB beginTransaction];
    
    // this is pretty lame.
    [_cacheDB executeUpdate:@"delete from folder"];
    
    for (NSString *folder in messages) {
        [_cacheDB executeUpdate:@"insert into folder (folder, subscribed) values (?,1)", folder];
    }
    
    [_cacheDB commit];
#endif

}

// FIXME: why am I returning strings here and not a LBFolder of some sort?

- (NSArray*) cachedFolders {
    
    // I'm just going to turn this off for now.  It's stupidly incomplete
    return [NSArray array];
    
#ifdef LBUSECACHE
    
    NSMutableArray *array = [NSMutableArray array];
    
    FMResultSet *rs = [_cacheDB executeQuery:@"select folder from folder"];
    while ([rs next]) {
        [array addObject:[rs stringForColumnIndex:0]];
    }
    
    return [array sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
#endif
}

- (NSArray*) cachedMessagesForFolder:(NSString *)folder {
    
    // I'm just going to turn this off for now.  It's stupidly incomplete
    return [NSArray array];
    
#ifdef LBUSECACHE
    
    NSMutableArray *messageArray = [NSMutableArray array];
    
    FMResultSet *rs = [_cacheDB executeQuery:@"select messageid, receivedDate from message where folder = ? order by receivedDate", folder];
    while ([rs next]) {
        
        NSString *messageFile = [NSString stringWithFormat:@"%@.letterboxmsg", [rs stringForColumnIndex:0]];
        
        // FIXME: check for the existence of the file...
        
        NSURL *messageCacheURL = [[_accountCacheURL URLByAppendingPathComponent:folder] URLByAppendingPathComponent:messageFile];
        
        LBMessage *message = [[[LBMessage alloc] init] autorelease];
        
        // FIXME: this isn't thread safe. (the file manager)
        if ([[NSFileManager defaultManager] fileExistsAtPath:[messageCacheURL path]]) {
            
            [message loadPropertyListRepresentationFromURL:messageCacheURL];
            
            [messageArray addObject:message];
        }
        else {
            // FIXME: make a list of messages to remove from the cache, as the FS rep isn't around.
        }
        
    }
    
    return messageArray;
#endif
}





@end
