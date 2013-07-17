//
//  QLKClient.m
//  QLabKit
//
//  Created by Zach Waugh on 7/9/13.
//  Copyright (c) 2013 Figure 53. All rights reserved.
//

#import "QLKClient.h"
#import "QLKDefines.h"
#import "QLKCue.h"
#import "QLKMessage.h"
#import "F53OSC.h"

@interface QLKClient ()

@property (strong) F53OSCClient *OSCClient;
@property (strong) NSMutableDictionary *callbacks;

@end

@implementation QLKClient

- (id)initWithHost:(NSString *)host port:(NSInteger)port
{
  self = [super init];
  if (!self) return nil;
  
  _callbacks = [[NSMutableDictionary alloc] init];
  _OSCClient = [[F53OSCClient alloc] init];
  _OSCClient.host = host;
  _OSCClient.port = port;
  _OSCClient.delegate = self;
  _connected = NO;
  
  return self;
}

- (void)setUseTCP:(BOOL)useTCP
{
  _useTCP = useTCP;
  self.OSCClient.useTcp = useTCP;
}

- (BOOL)connect
{
  return [self.OSCClient connect];
}

- (void)disconnect
{
  [self.OSCClient disconnect];
}

- (void)sendMessage:(F53OSCMessage *)message
{
  [self.OSCClient sendPacket:message];
}

- (void)sendMessage:(NSObject *)message toAddress:(NSString *)address
{
  [self sendMessage:message toAddress:address block:nil];
}

- (void)sendMessage:(NSObject *)message toAddress:(NSString *)address block:(QLKMessageHandlerBlock)block
{
  NSArray *messages = (message != nil) ? @[message] : nil;
  [self sendMessages:messages toAddress:address block:block];
}

- (void)sendMessages:(NSArray *)messages toAddress:(NSString *)address
{
  [self sendMessages:messages toAddress:address block:nil];
}

- (void)sendMessages:(NSArray *)messages toAddress:(NSString *)address block:(QLKMessageHandlerBlock)block
{
  if (block) {
    self.callbacks[address] = block;
  }
  
  // FIXME: need to use workspace prefix
  NSString *fullAddress = address; //[NSString stringWithFormat:@"%@%@", [self workspacePrefix], address];
  
#if DEBUG_OSC
  NSLog(@"[OSC ->] to: %@, data: %@", fullAddress, messages);
#endif
  
  F53OSCMessage *message = [F53OSCMessage messageWithAddressPattern:fullAddress arguments:messages];
  [self.OSCClient sendPacket:message];
}

#pragma mark - 

- (void)notifyAboutConnectionError
{
  
}

#pragma mark - F53OSCPacketDestination

- (void)takeMessage:(F53OSCMessage *)message
{
  [self processMessage:[QLKMessage messageWithOSCMessage:message]];
}

#pragma mark - F53OSCClientDelegate

- (void)clientDidConnect:(F53OSCClient *)client
{
  NSLog(@"clientDidConnect: %@", client);
}

- (void)clientDidDisconnect:(F53OSCClient *)client
{
  NSLog(@"clientDidDisconnect: %@, connected? %d", client, self.connected);
  
  // Only care if we think we're connected
  if (self.connected) {
    [self notifyAboutConnectionError];
  }
}

- (void)processMessage:(QLKMessage *)message
{
#if DEBUG_OSC
  NSLog(@"[osc] received message: %@", message);
#endif
  
  if ([message isReply]) {
    // Reply to a message we sent
    NSString *address = [message addressWithoutWorkspace:[self.delegate workspaceID]];

    id data = message.response;
    
    // Special case, want to update cue properties
    if ([address hasPrefix:@"/cue_id"]) {
      NSString *cueID = [address componentsSeparatedByString:@"/"][2];
      
      if ([data isKindOfClass:[NSDictionary class]]) {
        [self.delegate cueUpdated:cueID withProperties:data];
      }
    }
    
    QLKMessageHandlerBlock block = self.callbacks[address];
    
    if (block) {
			dispatch_async(dispatch_get_main_queue(), ^{
				block(data);
        
        // Clear handler for address
        [self.callbacks removeObjectForKey:address];
			});
    }
  } else if ([message isUpdate]) {
    // QLab has informed us of an update
    if ([message isWorkspaceUpdate]) {
      [self.delegate workspaceUpdated];
    } else if ([message isCueUpdate]) {
      [self.delegate cueUpdated:message.cueID];
    } else if ([message isPlaybackPositionUpdate]) {
      [self.delegate playbackPositionUpdated:message.cueID];
    } else if ([message isDisconnect]) {
      [self notifyAboutConnectionError];
    } else {
      NSLog(@"unhandled update message: %@", message.address);
    }
  }
}

@end
