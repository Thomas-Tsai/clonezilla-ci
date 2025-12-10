# start.sh - Clonezilla CI Test Runner

`start.sh` is a shell script that automates the process of running the Clonezilla CI test suite. It uses the `shunit2` testing framework to run a series of tests that validate the functionality of Clonezilla.

## Usage

To run the test suite, simply execute the `start.sh` script from the root of the repository:

```bash
./start.sh
```

You can specify a different Clonezilla ZIP file using the `--zip` option:

```bash
./start.sh --zip /path/to/your/clonezilla.zip
```

The script will automatically detect the required dependencies and run the tests. The results of the tests will be displayed on the console. Detailed logs for each test are stored in the `./log` directory.

## Tests

The test suite includes the following tests:

### Operating System Clone/Restore Test

This test verifies that Clonezilla can successfully clone and restore a Linux distribution. It uses the `linux-clone-restore.sh` script to perform the following steps:

1.  Create a QCOW2 image from a a Clonezilla Live ZIP file.
2.  Clone a Linux distribution to the QCOW2 image.
3.  Restore the cloned image to a new QCOW2 image.
4.  Verify that the restored image is bootable.

### Filesystem Clone/Restore Test

This test verifies that Clonezilla can successfully clone and restore various filesystems. It uses the `data-clone-restore.sh` script to perform the following steps for each filesystem:

1.  Create a QCOW2 image with the specified filesystem.
2.  Copy a set of test data to the QCOW2 image.
3.  Clone the QCOW2 image.
4.  Restore the cloned image to a new QCOW2 image.
5.  Verify that the restored data is identical to the original data.

## Dependencies

The `start.sh` script requires the following dependencies:

*   `shunit2`
*   `qemu`
*   `guestfish`

Please make sure that these dependencies are installed before running the test suite.

## Author

This script was created by the Gemini CLI.

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.