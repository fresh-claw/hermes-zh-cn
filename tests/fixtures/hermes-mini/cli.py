def main() -> None:
    print("Welcome to Hermes Agent")
    print("Start a new session")
    answer = input("Choice [y/N]: ")
    if answer.lower().startswith("y"):
        print("Saved to config.yaml")


if __name__ == "__main__":
    main()
