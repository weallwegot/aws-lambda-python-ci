
# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Upcoming Releases]

### Added

### Changed

### Fixed

## [1.1.0] - 2024-02-22

### Added

- Made the app environment key configurable as well as the s3 bucket for deployment.

## [1.0.1] - 2023-08-20

### Fixed

- Updated the subprocess function used to be more modern and high-level. This should fix the issue where bash non-zero return codes were not actually causing the pipeline to visibly fail.

## [1.0.0] - 2023-08-12

### Changed

- Lambda deployment updated to use s3 to bypass 50MB zip size limit.

### Fixed

- Deployment process fails and exits if one of the commands fails.

## [0.0.2] - 2023-05-24

### Fixed

- Fixed issue that caused environment variables to ignore string cases.

## [0.0.1] - 2022-01-08

### Changed

- A new home! Separated out deployment process logic from application code repository.

- Checks for Lambda state after creation/update of code and wait until Lambda is ready for next operation. This helps to avoid ResourceConflictExceptions if too many calls are being made in succession. More details available [here](https://aws.amazon.com/blogs/compute/tracking-the-state-of-lambda-functions/).

- More code reuse by using functions in the bash script