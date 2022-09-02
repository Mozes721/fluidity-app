import React from "react";
import { LinkButton } from "../Button";
import styles from "./NavBarModal.module.scss";

interface INavBarModal {
  handleModal: () => void;
  navLinks: ILinkButton[];
}

interface ILinkButton {
  children: string;
  size: "small" | "medium" | "large";
  type: "internal" | "external";
  handleClick: () => void;
}

const NavBarModal = ({ handleModal, navLinks }: INavBarModal) => {
  // if page is alredy on resources href id only otherwise switch page and then id
  return (
    <div className={styles.container}>
      {navLinks.map((link) => (
        <h4>
          <a onClick={() => handleModal()} href={`/resources#${link.children}`}>
            <LinkButton
              size={link.size}
              type={link.type}
              handleClick={() => {}}
            >
              {link.children}
            </LinkButton>
          </a>
        </h4>
      ))}
      <div className={styles.socials}>
        <img src="/assets/images/socials/twitter.svg" />
        <img src="/assets/images/socials/discord.svg" />
        <img src="/assets/images/socials/telegram.svg" />
      </div>
    </div>
  );
};

export default NavBarModal;