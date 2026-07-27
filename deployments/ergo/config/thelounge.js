"use strict";

module.exports = {
  public: true,
  host: "0.0.0.0",
  port: 9000,
  reverseProxy: false,
  maxHistory: 1000,
  prefetch: false,
  fileUpload: {
    enable: false,
    maxFileSize: 10240,
    baseUrl: null,
  },
  defaults: {
    name: "Pantalk Ergo",
    host: "ergo",
    port: 6667,
    password: "",
    tls: false,
    rejectUnauthorized: true,
    nick: "operator",
    username: "operator",
    realname: "Pantalk Operator",
    join: process.env.IRC_CHANNEL || "#ghost",
    leaveMessage: "",
  },
  lockNetwork: true,
  messageStorage: [],
};
