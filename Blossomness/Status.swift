//
//  Status.swift
//  Blossomness
//
//  Created by Ilya Makarevich on 6/15/21.
//

import Foundation

enum Status {
  //* Object detection hasn't started yet.
  case notStarted
  //* Object detection started detecting on new objects.
  case detecting
  //* Object detection is confirming on the same object.
  case confirming
  //* Object detection is searching the detected object.
  case searching
  //* Object detection has got search results on detected object.
  case searched
}
