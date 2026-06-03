#include "ZipInflate.h"
#include <string.h>
#include <zlib.h>

int contacttool_inflate_raw(const unsigned char *source, size_t source_length, unsigned char *destination, size_t destination_length) {
    if (source == NULL || destination == NULL) {
        return -1;
    }

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)source;
    stream.avail_in = (uInt)source_length;
    stream.next_out = destination;
    stream.avail_out = (uInt)destination_length;

    int status = inflateInit2(&stream, -MAX_WBITS);
    if (status != Z_OK) {
        return status;
    }

    status = inflate(&stream, Z_FINISH);
    inflateEnd(&stream);

    return status == Z_STREAM_END ? 0 : status;
}
