// TFLiteSymbolKeepalive.m
//
// tflite_flutter (0.12.x) on iOS resolves TFLite C symbols at runtime via
//   DynamicLibrary.process() -> dlsym(RTLD_DEFAULT, "TfLiteModelCreate")
//
// TensorFlowLiteC.framework is a STATIC vendored framework. Even when the
// symbols are linked into Runner via the Swift wrapper, Xcode's Release
// build strips them from the dynamic symbol table, making dlsym fail with:
//   "Failed to lookup symbol 'TfLiteModelCreate': symbol not found"
//
// This file holds explicit C references to the TFLite symbols used by
// tflite_flutter. Because `__keepalive` is marked __attribute__((used))
// and referenced from __attribute__((constructor)), the linker cannot
// drop the referenced symbols, and they are preserved in the dynamic
// symbol table of the Runner executable so dlsym(RTLD_DEFAULT) can find
// them.
//
// DO NOT CALL keepalive() from app code; its side-effect is purely
// link-time visibility.

#import <Foundation/Foundation.h>
#include <stddef.h>
#include <stdint.h>

// Opaque forward declarations (we only need addresses, not real types).
extern void *TfLiteModelCreate(const void *model_data, size_t model_size);
extern void *TfLiteModelCreateFromFile(const char *model_path);
extern void  TfLiteModelDelete(void *model);

extern void *TfLiteInterpreterOptionsCreate(void);
extern void  TfLiteInterpreterOptionsDelete(void *options);
extern void  TfLiteInterpreterOptionsSetNumThreads(void *options, int32_t num_threads);
extern void  TfLiteInterpreterOptionsAddDelegate(void *options, void *delegate);

extern void *TfLiteInterpreterCreate(const void *model, const void *options);
extern void  TfLiteInterpreterDelete(void *interpreter);
extern int   TfLiteInterpreterAllocateTensors(void *interpreter);
extern int   TfLiteInterpreterGetInputTensorCount(const void *interpreter);
extern void *TfLiteInterpreterGetInputTensor(const void *interpreter, int32_t input_index);
extern int   TfLiteInterpreterGetOutputTensorCount(const void *interpreter);
extern const void *TfLiteInterpreterGetOutputTensor(const void *interpreter, int32_t output_index);
extern int   TfLiteInterpreterInvoke(void *interpreter);
extern int   TfLiteInterpreterResizeInputTensor(void *interpreter, int32_t input_index, const int *input_dims, int32_t input_dims_size);

extern int          TfLiteTensorType(const void *tensor);
extern int32_t      TfLiteTensorNumDims(const void *tensor);
extern int32_t      TfLiteTensorDim(const void *tensor, int32_t dim_index);
extern size_t       TfLiteTensorByteSize(const void *tensor);
extern void        *TfLiteTensorData(const void *tensor);
extern const char  *TfLiteTensorName(const void *tensor);
extern int          TfLiteTensorCopyFromBuffer(void *tensor, const void *input_data, size_t input_data_size);
extern int          TfLiteTensorCopyToBuffer(const void *tensor, void *output_data, size_t output_data_size);

extern const char *TfLiteVersion(void);

__attribute__((used))
static const void *const _tflite_keepalive_table[] = {
    (const void *)&TfLiteModelCreate,
    (const void *)&TfLiteModelCreateFromFile,
    (const void *)&TfLiteModelDelete,
    (const void *)&TfLiteInterpreterOptionsCreate,
    (const void *)&TfLiteInterpreterOptionsDelete,
    (const void *)&TfLiteInterpreterOptionsSetNumThreads,
    (const void *)&TfLiteInterpreterOptionsAddDelegate,
    (const void *)&TfLiteInterpreterCreate,
    (const void *)&TfLiteInterpreterDelete,
    (const void *)&TfLiteInterpreterAllocateTensors,
    (const void *)&TfLiteInterpreterGetInputTensorCount,
    (const void *)&TfLiteInterpreterGetInputTensor,
    (const void *)&TfLiteInterpreterGetOutputTensorCount,
    (const void *)&TfLiteInterpreterGetOutputTensor,
    (const void *)&TfLiteInterpreterInvoke,
    (const void *)&TfLiteInterpreterResizeInputTensor,
    (const void *)&TfLiteTensorType,
    (const void *)&TfLiteTensorNumDims,
    (const void *)&TfLiteTensorDim,
    (const void *)&TfLiteTensorByteSize,
    (const void *)&TfLiteTensorData,
    (const void *)&TfLiteTensorName,
    (const void *)&TfLiteTensorCopyFromBuffer,
    (const void *)&TfLiteTensorCopyToBuffer,
    (const void *)&TfLiteVersion,
};

__attribute__((constructor))
static void _tflite_keepalive_touch(void) {
    // Prevent the optimizer from eliminating the keepalive table even
    // under aggressive LTO.
    volatile const void *const *p = _tflite_keepalive_table;
    (void)p;
}
