//
//  MPMessagePackReader.m
//  MPMessagePack
//
//  Created by Gabriel on 7/3/14.
//  Copyright (c) 2014 Gabriel Handford. All rights reserved.
//

#import "MPMessagePackReader.h"

#include "cmp.h"

#import "MPOrderedDictionary.h"

#define MAX_DATA_LENGTH (1024 * 1024 * 100) // 100MB

@interface MPMessagePackReader ()
@property NSData *data;
@property size_t index;
@end

@implementation MPMessagePackReader

- (id)readFromContext:(cmp_ctx_t *)context options:(MPMessagePackReaderOptions)options error:(NSError * __autoreleasing *)error {
  cmp_object_t obj;
  if (!cmp_read_object(context, &obj)) {
    return [self returnNilWithErrorCode:200 description:@"Unable to read object" error:error];
  }
  
  switch (obj.type) {

    case CMP_TYPE_NIL: return [NSNull null];
    case CMP_TYPE_BOOLEAN: return @(obj.as.boolean);
      
    case CMP_TYPE_BIN8:
    case CMP_TYPE_BIN16:
    case CMP_TYPE_BIN32: {
      uint32_t length = obj.as.bin_size;
      if (length == 0) return [NSData data];
      if (length > MAX_DATA_LENGTH) {
        return [self returnNilWithErrorCode:298 description:@"Reached max data length, data might be malformed" error:error];
      }
      NSMutableData *data = [NSMutableData dataWithLength:length];
      context->read(context, [data mutableBytes], length);
      return data;
    }

    case CMP_TYPE_POSITIVE_FIXNUM: return @(obj.as.u8);
    case CMP_TYPE_NEGATIVE_FIXNUM:return @(obj.as.s8);
    case CMP_TYPE_FLOAT: return @(obj.as.flt);
    case CMP_TYPE_DOUBLE: return @(obj.as.dbl);
    case CMP_TYPE_UINT8: return @(obj.as.u8);
    case CMP_TYPE_UINT16: return @(obj.as.u16);
    case CMP_TYPE_UINT32: return @(obj.as.u32);
    case CMP_TYPE_UINT64: return @(obj.as.u64);
    case CMP_TYPE_SINT8: return @(obj.as.s8);
    case CMP_TYPE_SINT16: return @(obj.as.s16);
    case CMP_TYPE_SINT32: return @(obj.as.s32);
    case CMP_TYPE_SINT64: return @(obj.as.s64);

    case CMP_TYPE_FIXSTR:
    case CMP_TYPE_STR8:
    case CMP_TYPE_STR16:
    case CMP_TYPE_STR32: {
      uint32_t length = obj.as.str_size;
      if (length == 0) return @"";
      if (length > MAX_DATA_LENGTH) {
        return [self returnNilWithErrorCode:298 description:@"Reached max data length, data might be malformed" error:error];
      }
      NSMutableData *data = [NSMutableData dataWithLength:length];
      context->read(context, [data mutableBytes], length);
      return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }

    case CMP_TYPE_FIXARRAY:
    case CMP_TYPE_ARRAY16:
    case CMP_TYPE_ARRAY32: {
      uint32_t length = obj.as.array_size;
      return [self readArrayFromContext:context options:options length:length error:error];
    }
      
    case CMP_TYPE_FIXMAP:
    case CMP_TYPE_MAP16:
    case CMP_TYPE_MAP32: {
      uint32_t length = obj.as.map_size;
      return [self readDictionaryFromContext:context options:options length:length error:error];
    }
      
    case CMP_TYPE_EXT8:
    case CMP_TYPE_EXT16:
    case CMP_TYPE_EXT32:
    case CMP_TYPE_FIXEXT1:
    case CMP_TYPE_FIXEXT2:
    case CMP_TYPE_FIXEXT4:
    case CMP_TYPE_FIXEXT8:
    case CMP_TYPE_FIXEXT16:
      
    default: {
      return [self returnNilWithErrorCode:201 description:@"Unsupported object type" error:error];
    }
  }
}

- (NSMutableArray *)readArrayFromContext:(cmp_ctx_t *)context options:(MPMessagePackReaderOptions)options length:(uint32_t)length error:(NSError * __autoreleasing *)error {
  NSUInteger capacity = length < 1000 ? length : 1000;
  NSMutableArray *array = [NSMutableArray arrayWithCapacity:capacity];
  for (NSInteger i = 0; i < length; i++) {
    id obj = [self readFromContext:context options:options error:error];
    if (!obj) {
      return [self returnNilWithErrorCode:202 description:@"Unable to read object" error:error];
    }
    [array addObject:obj];
  }
  return array;
}

- (NSMutableDictionary *)readDictionaryFromContext:(cmp_ctx_t *)context options:(MPMessagePackReaderOptions)options length:(uint32_t)length error:(NSError * __autoreleasing *)error {
  NSUInteger capacity = length < 1000 ? length : 1000;

  id dict = nil;
  if ((options & MPMessagePackReaderOptionsUseOrderedDictionary) == MPMessagePackReaderOptionsUseOrderedDictionary) {
    dict = [[MPOrderedDictionary alloc] initWithCapacity:capacity];
  } else {
    dict = [NSMutableDictionary dictionaryWithCapacity:capacity];
  }
  
  for (NSInteger i = 0; i < length; i++) {
    id key = [self readFromContext:context options:options error:error];
    if (!key) {
      return [self returnNilWithErrorCode:203 description:@"Unable to read object" error:error];
    }
    id value = [self readFromContext:context options:options error:error];
    if (!value) {
      return [self returnNilWithErrorCode:204 description:@"Unable to read object" error:error];
    }
    dict[key] = value;
  }
  return dict;
}

- (id)returnNilWithErrorCode:(NSInteger)errorCode description:(NSString *)description error:(NSError * __autoreleasing *)error {
  if (error) *error = [NSError errorWithDomain:@"MPMessagePack" code:errorCode userInfo:@{NSLocalizedDescriptionKey: description}];
  return nil;
}

- (size_t)read:(void *)data limit:(size_t)limit {
  if (_index + limit > [_data length]) {
    NSLog(@"No more data");
    return 0;
  }
  [_data getBytes:data range:NSMakeRange(_index, limit)];
  
//  NSData *read = [NSData dataWithBytes:data length:limit];
//  NSLog(@"Read bytes: %@", read);
  
  _index += limit;
  return limit;
}

static bool mp_reader(cmp_ctx_t *ctx, void *data, size_t limit) {
  MPMessagePackReader *mp = (__bridge MPMessagePackReader *)ctx->buf;
  return [mp read:data limit:limit];
}

static size_t mp_writer(cmp_ctx_t *ctx, const void *data, size_t count) {
  return 0;
}

- (id)readData:(NSData *)data options:(MPMessagePackReaderOptions)options error:(NSError * __autoreleasing *)error {
  _data = data;
  _index = 0;
  
  cmp_ctx_t ctx;
  cmp_init(&ctx, (__bridge void *)self, mp_reader, mp_writer);
  return [self readFromContext:&ctx options:options error:error];
}

+ (id)readData:(NSData *)data error:(NSError * __autoreleasing *)error {
  return [self readData:data options:0 error:error];
}

+ (id)readData:(NSData *)data options:(MPMessagePackReaderOptions)options error:(NSError * __autoreleasing *)error {
  MPMessagePackReader *messagePackReader = [[MPMessagePackReader alloc] init];
  id obj = [messagePackReader readData:data options:options error:error];
  
  if (!obj) {
    if (error) *error = [NSError errorWithDomain:@"MPMessagePack" code:299 userInfo:@{NSLocalizedDescriptionKey: @"Unable to read object"}];
    return nil;
  }
  
  return obj;
}

@end
