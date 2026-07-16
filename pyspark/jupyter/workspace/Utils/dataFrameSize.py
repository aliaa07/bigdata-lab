def dfSizeEstimator(df, in_mb=False):
    bytes_size = df._jdf.queryExecution().optimizedPlan().stats().sizeInBytes()
    if in_mb:
        return bytes_size / (1024 ** 2)
    else:
        return bytes_size