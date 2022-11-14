# Pirex-GMX

### Setup

IDE: VSCode 1.73.0 (Universal)

Forge: 0.2.0

From inside the project directory:
1. Install contract dependencies `forge i`
2. Compile contracts `forge build`
3. Set up and run tests
    3a. Create the test variables helper script `cp scripts/loadEnv.example.sh scripts/loadEnv.sh`
    3b. Define the values within the newly-created file in 3a
    3c. Run the test helper script `scripts/forgeTest.sh` (along with any `forge test` arguments, flags, options, etc.)
